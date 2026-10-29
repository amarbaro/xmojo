# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Field and struct modifiers: rename, aliases, skip, defaults, a struct-wide rename policy,
# strict unknown-field checking and enum arm names. Mojo cannot reflect on a type's
# parameters, so `Field` republishes its configuration as comptime members (`FieldMeta`)
# that the reflection code reads back through `downcast`.
from std.builtin.rebind import downcast
from std.collections.string.string_span import get_static_string
from std.reflection import reflect

comptime Base = Movable & Deinitable


trait FieldMeta(Deinitable, Movable):
    comptime serde_name: Optional[String]
    comptime serde_extra: Optional[List[String]]
    comptime serde_skip: Bool
    comptime serde_fill_if_missing: Bool

    @staticmethod
    def serde_filled() -> Self:
        """The value of a skipped or absent field: the `default` if given, else `T()`."""
        ...


struct Field[
    T: Base,
    *,
    rename: Optional[String] = None,
    extra_names: Optional[List[String]] = None,
    skip: Bool = False,
    default: Optional[T] = None,
](
    Copyable where conforms_to(T, Copyable),
    Defaultable where conforms_to(T, Defaultable),
    FieldMeta,
):
    comptime serde_name = Self.rename
    comptime serde_extra = Self.extra_names
    comptime serde_skip = Self.skip
    # An Optional payload stays absence-tolerant through the wrapper.
    comptime serde_fill_if_missing = Self.skip or Bool(Self.default) or is_optional[Self.T]()

    var value: Self.T

    def __init__(out self):
        comptime if Self.default:
            self.value = materialize[Self.default.value()]()
        elif conforms_to(Self.T, Defaultable):
            self.value = Self.T()
        else:
            comptime assert False, "Field: the type is not Defaultable and has no default"

    @implicit
    def __init__(out self, var value: Self.T):
        self.value = value^

    @always_inline
    def __getitem__(ref self) -> ref[self.value] Self.T:
        return self.value

    @staticmethod
    def serde_filled() -> Self:
        return Self()


comptime Defaulted[T: Base, value: T] = Field[T, default=value]
comptime Skip[T: Base] = Field[T, skip=True]
comptime Rename[T: Base, s: String] = Field[T, rename=s]


@fieldwise_init
struct RenamePolicy(Equatable, ImplicitlyCopyable):
    var _value: Int

    comptime SnakeCase = Self(0)
    comptime CamelCase = Self(1)
    comptime PascalCase = Self(2)
    comptime KebabCase = Self(3)
    comptime ScreamingSnakeCase = Self(4)
    comptime ScreamingKebabCase = Self(5)
    comptime LowerCase = Self(6)
    comptime UpperCase = Self(7)

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


trait RenameAll:
    """A struct sets the wire-name convention of all its fields; a field's `rename` wins."""
    comptime FieldRenamePolicy: RenamePolicy


trait DenyUnknownFields:
    """An attribute or child element that binds no field raises instead of being ignored."""
    pass


trait ArmName:
    """The name a `Variant` arm type takes on the wire."""
    comptime serde_arm_name: StaticString


def is_optional[T: AnyType]() -> Bool:
    return reflect[T].base_name() == "Optional"


def is_skipped[FT: AnyType]() -> Bool:
    comptime if conforms_to(FT, FieldMeta):
        return downcast[FT, FieldMeta].serde_skip
    else:
        return False


def fill_if_missing[FT: AnyType]() -> Bool:
    comptime if conforms_to(FT, FieldMeta):
        return downcast[FT, FieldMeta].serde_fill_if_missing
    else:
        return is_optional[FT]()


def arm_tag[AT: AnyType]() -> String:
    comptime if conforms_to(AT, ArmName):
        return String(downcast[AT, ArmName].serde_arm_name)
    return String(reflect[AT].name())


def _wire_name[T: AnyType, FT: AnyType](declared: StaticString) -> String:
    """Precedence: the field's `rename`, then the struct's `RenameAll` policy, then the name."""
    comptime if conforms_to(FT, FieldMeta):
        comptime FM = downcast[FT, FieldMeta]
        comptime if FM.serde_name:
            return String(FM.serde_name.value())
    comptime if conforms_to(T, RenameAll):
        return apply_rename_policy[downcast[T, RenameAll].FieldRenamePolicy](declared)
    return String(declared)


def static_wire_name[T: AnyType, FT: AnyType, declared: StaticString]() -> StaticString:
    """The wire name, computed at compile time and interned."""
    return get_static_string[_wire_name[T, FT](declared)]()


def has_unique_wire_names[T: AnyType]() -> Bool:
    comptime r = reflect[T]
    comptime for i in range(r.field_count()):
        comptime if not is_skipped[r.field_types()[i]]():
            var wi = _wire_name[T, r.field_types()[i]](r.field_names()[i])
            comptime for j in range(i + 1, r.field_count()):
                comptime if not is_skipped[r.field_types()[j]]():
                    if wi == _wire_name[T, r.field_types()[j]](r.field_names()[j]):
                        return False
    return True


def _is_upper(c: Int) -> Bool:
    return c >= ord("A") and c <= ord("Z")


def _split_words(name: StringSlice) -> List[String]:
    """Lowercased words: `_` and `-` split, and so do case changes (`fooBar`, `HTTPServer`)."""
    var words = List[String]()
    var cur = String()
    var b = name.as_bytes()
    var n = len(b)
    for i in range(n):
        var c = Int(b[i])
        if c == ord("_") or c == ord("-"):
            if cur.byte_length() != 0:
                words.append(cur^)
                cur = String()
            continue
        if cur.byte_length() != 0:
            var prev = Int(b[i - 1])
            var nxt = Int(b[i + 1]) if i + 1 < n else 0
            var lower_prev = (prev >= ord("a") and prev <= ord("z")) or (prev >= ord("0") and prev <= ord("9"))
            var lower_next = nxt >= ord("a") and nxt <= ord("z")
            if _is_upper(c) and (lower_prev or (_is_upper(prev) and lower_next)):
                words.append(cur^)
                cur = String()
        cur += chr(c + 32 if _is_upper(c) else c)
    if cur.byte_length() != 0:
        words.append(cur^)
    return words^


def _capitalize(word: String) -> String:
    var out = String()
    for cp in word.codepoint_slices():
        out += String(cp).upper() if out.byte_length() == 0 else String(cp)
    return out^


def apply_rename_policy[policy: RenamePolicy](declared: StaticString) -> String:
    comptime snake = policy == RenamePolicy.SnakeCase or policy == RenamePolicy.ScreamingSnakeCase
    comptime kebab = policy == RenamePolicy.KebabCase or policy == RenamePolicy.ScreamingKebabCase
    comptime upper = (
        policy == RenamePolicy.ScreamingSnakeCase
        or policy == RenamePolicy.ScreamingKebabCase
        or policy == RenamePolicy.UpperCase
    )
    var words = _split_words(declared)
    var out = String()
    for i in range(len(words)):
        if i > 0:
            out += "_" if snake else ("-" if kebab else "")
        comptime if upper:
            out += words[i].upper()
        elif policy == RenamePolicy.CamelCase:
            out += words[i] if i == 0 else _capitalize(words[i])
        elif policy == RenamePolicy.PascalCase:
            out += _capitalize(words[i])
        else:
            out += words[i]
    return out^
