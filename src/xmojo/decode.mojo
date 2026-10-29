# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# from_xml[T]: fill T from the arena DOM. Library types decode through `XmlDecode`
# extensions; any other struct is filled field by field through reflection.
#
# Mapping:
#   struct field  <- attribute of same local name, else repeated child elements of that local
#                    name, else `text` (element content) for a field literally named `text`
#   List[T]       <- all children with that name        Optional[T] <- None if absent
#   String/Int/Float/Bool <- attribute value or element text
#   Dict[String, V] named `attrs` <- the attributes; any other Dict <- children keyed by name
#   Variant of unit arms <- the arm whose ArmName (or type name) equals the text
from std.builtin.rebind import rebind_var, downcast
from std.reflection import reflect
from std.utils import Variant
from .dom import Doc, parse, NONE
from .field import (
    Base,
    Field,
    FieldMeta,
    DenyUnknownFields,
    arm_tag,
    fill_if_missing,
    has_unique_wire_names,
    is_skipped,
    static_wire_name,
)

comptime K_ELEMENT = 0   # one node
comptime K_GROUP = 1     # children of `node` whose local-name id == `at`
comptime K_ATTR = 2      # attribute record `at`
comptime K_TEXT = 3      # text content of `node`
comptime K_ATTRS = 4     # all attributes of `node`, as a map (field literally named "attrs")
comptime K_ABSENT = -1   # _find: the element has nothing for this field

comptime DocPtr = Pointer[Doc, MutUntrackedOrigin]   # the Doc outlives every decode call


@fieldwise_init
struct Cursor(ImplicitlyCopyable):
    var kind: Int
    var node: Int
    var at: Int                 # K_ATTR: index into Doc.attrs; K_GROUP: local-name id (NONE: absent)
    var field: Int              # declaration index in the struct being decoded
    var name: StaticString      # wire name, for messages


@fieldwise_init
struct XmlIn(ImplicitlyCopyable):
    """What is at the cursor: the value one decode call reads."""
    var doc: DocPtr
    var cur: Cursor

    def at(self, c: Cursor) -> Self:
        return Self(self.doc, c)

    def single_node(self) raises -> Int:
        if self.cur.kind == K_ELEMENT or self.cur.kind == K_TEXT:
            return self.cur.node
        if self.cur.kind == K_GROUP:
            var c = self.doc[].first_child(self.cur.node, Int32(self.cur.at))
            if c < 0:
                raise Error("xmojo: missing element <", self.cur.name, ">")
            return c
        raise Error("xmojo: attribute @", self.cur.name, " used where an element was expected")

    def scalar_text(self) raises -> String:
        if self.cur.kind == K_ATTR:
            ref a = self.doc[].attrs[self.cur.at]
            return self.doc[]._pooled(a.off, a.len)
        return self.doc[].text(self.single_node())

    def present(self) -> Bool:
        if self.cur.kind == K_GROUP:
            return self.doc[].first_child(self.cur.node, Int32(self.cur.at)) >= 0
        if self.cur.kind == K_TEXT:
            return self.doc[].has_text(self.cur.node)
        return True


trait XmlDecode:
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        ...


def decode[T: AnyType](src: XmlIn) raises -> T:
    comptime if conforms_to(T, XmlDecode):
        return T.xml_decode(src)
    elif conforms_to(T, Deinitable):
        return _decode_struct[T](src)
    else:
        comptime assert False, "xmojo: cannot decode a linear type"


def _parse_bool(src: XmlIn) raises -> Bool:
    var text = src.scalar_text()
    var s = text.strip()
    if s == "true" or s == "1":
        return True
    if s == "false" or s == "0":
        return False
    raise Error("xmojo: not a boolean: ", s)


__extension Bool(XmlDecode):
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        return _parse_bool(src)


__extension String(XmlDecode):
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        return src.scalar_text()


__extension SIMD(XmlDecode):
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        comptime assert Self.length == 1, "xmojo: only scalar SIMD fields"
        comptime if Self.dtype == DType.bool:
            return rebind[Self](Scalar[DType.bool](_parse_bool(src)))
        var text = src.scalar_text()
        var s = text.strip()
        try:
            comptime if Self.dtype.is_floating_point():
                return rebind[Self](Scalar[Self.dtype](Float64(s)))
            else:
                return rebind[Self](Scalar[Self.dtype](Int(s)))
        except:
            raise Error("xmojo: not a number: ", s)


__extension Optional(XmlDecode):
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        comptime assert conforms_to(Self.T, Base), "xmojo: Optional needs a Movable payload"
        comptime PT = downcast[Self.T, Base]
        if not src.present():
            return rebind_var[Self](Optional[PT]())
        return rebind_var[Self](Optional[PT](decode[PT](src)))


__extension List(XmlDecode):
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        comptime ET = downcast[Self.T, Base]
        var items: List[Int]
        if src.cur.kind == K_GROUP:
            items = src.doc[].children_local(src.cur.node, Int32(src.cur.at))
        elif src.cur.kind == K_ELEMENT:
            items = [src.cur.node]
        else:
            raise Error("xmojo: attribute @", src.cur.name, " cannot be a sequence")
        var result = List[ET](capacity=len(items))
        for n in items:
            result.append(decode[ET](src.at(Cursor(K_ELEMENT, n, 0, 0, ""))))
        return rebind_var[Self](result^)


__extension Dict(XmlDecode):
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        comptime assert reflect[Self.K].name() == reflect[String].name(), "xmojo: map keys must be String"
        comptime VT = downcast[Self.V, Base]
        var result = Dict[String, VT]()
        if src.cur.kind == K_ATTRS:
            var n = src.cur.node
            var a0 = Int(src.doc[].nodes[n].attr0)
            var keys = src.doc[].attr_names(n)
            for k in range(len(keys)):
                result[keys[k]] = decode[VT](src.at(Cursor(K_ATTR, n, a0 + k, 0, "")))
        else:
            var n = src.single_node()
            for key in src.doc[].child_local_names(n):
                var kids = src.doc[].children_named(n, key)
                result[key] = decode[VT](src.at(Cursor(K_ELEMENT, kids[len(kids) - 1], 0, 0, "")))
        return rebind_var[Self](result^)


__extension Variant(XmlDecode):
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        var text = String(src.scalar_text().strip())
        comptime for i in range(Self.Ts.length):
            comptime AT = downcast[Self.Ts[i], Base]
            if text == arm_tag[AT]():
                comptime if conforms_to(AT, Defaultable):
                    return Self(downcast[AT, Base & Defaultable]())
                else:
                    raise Error("xmojo: enum arms must be unit variants")
        raise Error("xmojo: enum '", src.cur.name, "' has no arm '", text, "'")


__extension Field(XmlDecode):
    @staticmethod
    def xml_decode(src: XmlIn) raises -> Self:
        return Self(decode[Self.T](src))


def _find(d: Doc, n: Int, field: Int, key: StringSlice, name: StaticString) -> Cursor:
    """Where field `key` of element `n` comes from: an attribute of that local name, else child
    elements of that local name, else the element's text (`text`) or attribute map (`attrs`).
    K_ABSENT when the element has none of these: an Optional is then None, a Skip or Defaulted
    field takes its default, anything else raises "missing field"."""
    var id = d._id(String(key))
    if id != NONE:
        var a = d.attr_index(n, id)
        if a >= 0:
            return Cursor(K_ATTR, n, a, field, name)
        if d.first_child(n, id) >= 0:
            return Cursor(K_GROUP, n, Int(id), field, name)
    if key == "text":   # no text is the empty string
        return Cursor(K_TEXT, n, 0, field, name)
    if key == "attrs":
        return Cursor(K_ATTRS, n, 0, field, name)
    return Cursor(K_ABSENT, n, 0, field, name)


def _bind[T: AnyType, FT: AnyType, i: Int](d: Doc, n: Int, mut fields: List[Cursor]):
    """Append field i's cursor: found under its wire name, else under an `extra_names` alias.
    An absent field gets none, except an absent List, which decodes as []. Kept out of the
    comptime field loop: an Optional built there plus the alias loop never finishes compiling
    on Mojo 1.1."""
    comptime name = static_wire_name[T, FT, reflect[T].field_names()[i]]()
    var c = _find(d, n, i, name, name)
    comptime if conforms_to(FT, FieldMeta):
        comptime extra = downcast[FT, FieldMeta].serde_extra
        comptime if Bool(extra):
            var aliases = materialize[extra.value()]()
            var k = 0
            while c.kind == K_ABSENT and k < len(aliases):
                c = _find(d, n, i, aliases[k], name)
                k += 1
    comptime is_list = reflect[FT].base_name() == "List"
    if c.kind != K_ABSENT:
        fields.append(c)
    elif is_list:
        fields.append(Cursor(K_GROUP, n, Int(NONE), i, name))


def _deny_unknown(d: Doc, n: Int, fields: List[Cursor]) raises:
    """For DenyUnknownFields structs: every attribute (namespace declarations aside) and every
    child element of `n` must have bound a field."""
    var all_attrs = False
    var bound = List[Int32]()
    for f in fields:
        if f.kind == K_ATTRS:
            all_attrs = True
        elif f.kind == K_ATTR:
            bound.append(d.local_of[Int(d.attrs[f.at].name)])
        elif f.kind == K_GROUP:
            bound.append(Int32(f.at))
    var a0 = Int(d.nodes[n].attr0)
    for k in range(a0, a0 + Int(d.nodes[n].nattr)):
        var local = d.local_of[Int(d.attrs[k].name)]
        if not all_attrs and d.attrs[k].ns != 2 and d.names[Int(d.attrs[k].name)] != "xmlns" and local not in bound:
            raise Error("xmojo: unknown attribute @", d.names[Int(d.attrs[k].name)])
    for c in d.children(n):
        if d.local_of[Int(d.nodes[c].name)] not in bound:
            raise Error("xmojo: unknown element <", d.name(c), ">")


def _all_dtors_trivial[T: AnyType]() -> Bool:
    comptime r = reflect[T]
    comptime for i in range(r.field_count()):
        comptime if not conforms_to(r.field_types()[i], TrivialRegisterPassable):
            return False
    return True


def _decode_struct[T: Deinitable](src: XmlIn, out result: T) raises:
    comptime r = reflect[T]
    comptime assert r.is_struct(), "xmojo: from_xml needs a struct"
    comptime assert has_unique_wire_names[T](), "xmojo: two fields have the same wire name"
    comptime if conforms_to(T, Defaultable):
        result = downcast[T, Defaultable & Deinitable]()
    else:
        comptime assert _all_dtors_trivial[T](), (
            "xmojo: a struct that is not Defaultable may only hold trivially destructible fields"
        )
        __mlir_op.`lit.ownership.mark_initialized`(__get_mvalue_as_litref(result))
    var n = src.single_node()
    var fields = List[Cursor]()
    comptime for i in range(r.field_count()):
        comptime if not is_skipped[r.field_types()[i]]():
            _bind[T, r.field_types()[i], i](src.doc[], n, fields)
    comptime if conforms_to(T, DenyUnknownFields):
        _deny_unknown(src.doc[], n, fields)
    var seen = Array[Bool, r.field_count()](fill=False)
    for c in fields:
        comptime for i in range(r.field_count()):
            comptime if not is_skipped[r.field_types()[i]]():
                if c.field == i:
                    comptime assert conforms_to(r.field_types()[i], Base), "xmojo: fields must be Movable"
                    comptime FT = downcast[r.field_types()[i], Base]
                    r.field_ref[i](result) = decode[FT](src.at(c))
                    seen[i] = True
    comptime for i in range(r.field_count()):
        if not seen[i]:
            comptime FT = r.field_types()[i]
            comptime if fill_if_missing[FT]():
                comptime if conforms_to(FT, FieldMeta):
                    r.field_ref[i](result) = downcast[FT, FieldMeta].serde_filled()
                else:
                    comptime assert conforms_to(FT, Base & Defaultable), "xmojo: missing field must be Defaultable"
                    ref f = r.field_ref[i](result)
                    f = type_of(f)()
            else:
                raise Error("missing field: ", r.field_names()[i])


def from_xml[T: Movable & Deinitable](s: StringSlice, entities: Dict[String, String] = Dict[String, String]()) raises -> T:
    """Parse XML text and fill `T` from the root element (see module doc for the mapping).
    `entities` as for `parse`."""
    var doc: Doc
    try:
        doc = parse(s, entities)
    except e:
        raise Error(e)
    var src = XmlIn(Pointer(to=doc).unsafe_origin_cast[MutUntrackedOrigin](), Cursor(K_ELEMENT, doc.root(), 0, 0, ""))
    var result = decode[T](src)
    _ = doc^
    return result^
