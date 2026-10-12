# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# emberserde format over the arena DOM. `from_xml[T]` = emberserde's reflection driver
# walking struct fields; this file only answers "what is at the cursor".
#
# Mapping (v0):
#   struct field  <- attribute of same local name, else repeated child elements of that local
#                    name, else `text` (element content) for a field literally named `text`
#   List[T]       <- all children with that name        Optional[T] <- None if absent
#   String/Int/Float/Bool <- attribute value or element text
from std.builtin.rebind import rebind_var, downcast
from std.reflection import reflect
from emberserde import (
    Deserializer,
    SeqDerState,
    MapDerState,
    StructDerState,
    TupleDerState,
    EnumDerState,
    DeserializationError,
    DerErrorKind,
    deserialize,
    FieldMeta,
    DenyUnknownFields,
)
from emberserde.field_meta import is_skipped, static_wire_name
from .dom import Doc, parse, NONE

comptime K_ELEMENT = 0   # one node
comptime K_GROUP = 1     # children of `node` whose local-name id == `at`
comptime K_ATTR = 2      # attribute record `at`
comptime K_TEXT = 3      # text content of `node`
comptime K_ATTRS = 4     # all attributes of `node`, as a map (field literally named "attrs")
comptime K_ABSENT = -1   # _find: the element has nothing for this field


@fieldwise_init
struct Cursor(ImplicitlyCopyable):
    var kind: Int
    var node: Int
    var at: Int                 # K_ATTR: index into Doc.attrs; K_GROUP: local-name id (NONE: absent)
    var field: Int              # declaration index in the struct being decoded
    var name: StaticString      # wire name, for messages


def _err(msg: String, kind: DerErrorKind = DerErrorKind.InvalidValue) -> DeserializationError:
    return DeserializationError(msg, kind)


def _find(d: Doc, n: Int, field: Int, key: StringSlice, name: StaticString) -> Cursor:
    """Where field `key` of element `n` comes from: an attribute of that local name, else child
    elements of that local name, else the element's text (`text`) or attribute map (`attrs`).
    K_ABSENT when the element has none of these: emberserde then applies its own rules (an
    Optional is None, a Skip or Defaulted field takes its default, anything else raises
    MissingField)."""
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
    An absent field gets none (emberserde then applies Optional/default/MissingField), except
    an absent List, which decodes as []. Kept out of begin_struct's comptime loop: an
    Optional built there plus the alias loop never finishes compiling on Mojo 1.1."""
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


def _deny_unknown(d: Doc, n: Int, fields: List[Cursor]) raises DeserializationError:
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
            raise _err("xmojo: unknown attribute @" + d.names[Int(d.attrs[k].name)], DerErrorKind.UnknownField)
    for c in d.children(n):
        if d.local_of[Int(d.nodes[c].name)] not in bound:
            raise _err("xmojo: unknown element <" + d.name(c) + ">", DerErrorKind.UnknownField)


@fieldwise_init
struct XmlSeqDe[origin: ImmOrigin](SeqDerState):
    var doc: Pointer[Doc, Self.origin]
    var items: List[Int]
    var i: Int

    def has_next(mut self) raises DeserializationError -> Bool:
        return self.i < len(self.items)

    def expect_element[T: AnyType](mut self) raises DeserializationError -> T:
        var sub = XmlDeserializer(doc=self.doc, cur=Cursor(K_ELEMENT, self.items[self.i], 0, 0, ""))
        self.i += 1
        return deserialize[T](sub)

    def end(mut self) raises DeserializationError:
        pass


@fieldwise_init
struct XmlStructDe[origin: ImmOrigin](StructDerState):
    var doc: Pointer[Doc, Self.origin]
    var fields: List[Cursor]   # one cursor per declared, non-skipped field
    var i: Int

    def expect_field_index[T: AnyType](mut self) raises DeserializationError -> Optional[Int]:
        if self.i >= len(self.fields):
            return None
        return self.fields[self.i].field

    def expect_field_value[T: AnyType](mut self) raises DeserializationError -> T:
        var sub = XmlDeserializer(doc=self.doc, cur=self.fields[self.i])
        self.i += 1
        return deserialize[T](sub)

    def skip_value(mut self) raises DeserializationError:
        self.i += 1

    def end(mut self) raises DeserializationError:
        pass


struct XmlUnsupportedDe(TupleDerState):
    def __init__(out self):
        pass

    def expect_element[T: AnyType](mut self) raises DeserializationError -> T:
        raise _err("xmojo: tuples are not supported", DerErrorKind.TypeMismatch)

    def end(mut self) raises DeserializationError:
        pass


comptime MAP_MODE_ATTRS = 0    # keys = attribute names of `node`
comptime MAP_MODE_CHILDREN = 1  # keys = distinct local names of `node`'s children


@fieldwise_init
struct XmlMapDe[origin: ImmOrigin](MapDerState):
    var doc: Pointer[Doc, Self.origin]
    var node: Int
    var mode: Int
    var keys: List[String]
    var i: Int

    def has_next(mut self) raises DeserializationError -> Bool:
        return self.i < len(self.keys)

    def expect_key[T: AnyType](mut self) raises DeserializationError -> T:
        # `conforms_to(T, Movable)` is true for every scalar (Int included): it only checks
        # the trait, not the concrete type, so it let a `Dict[Int, V]` field compile and then
        # reinterpret a `String`'s bytes as an `Int`. Canonical-name equality is the real
        # check (`_type_is_eq` was removed; this is emberserde's own stand-in, see
        # `serialize/impls.mojo`'s `Span` extension).
        comptime assert reflect[T].name() == reflect[String].name(), "xmojo: map keys must be String"
        return rebind_var[downcast[T, Movable & Deinitable]](self.keys[self.i].copy())

    def expect_value[T: AnyType](mut self) raises DeserializationError -> T:
        var k = self.i
        self.i += 1
        if self.mode == MAP_MODE_ATTRS:
            var cur = Cursor(K_ATTR, self.node, Int(self.doc[].nodes[self.node].attr0) + k, 0, "")
            var sub = XmlDeserializer(doc=self.doc, cur=cur)
            return deserialize[T](sub)
        var kids = self.doc[].children_named(self.node, self.keys[k])
        var sub = XmlDeserializer(doc=self.doc, cur=Cursor(K_ELEMENT, kids[len(kids) - 1], 0, 0, ""))
        return deserialize[T](sub)

    def end(mut self) raises DeserializationError:
        pass


@fieldwise_init
struct XmlEnumDe(EnumDerState):
    var idx: Int

    def variant_index(mut self) raises DeserializationError -> Int:
        return self.idx

    def expect_payload[T: AnyType](mut self) raises DeserializationError -> T:
        comptime if conforms_to(T, Defaultable):
            return T()
        else:
            raise _err("xmojo: enum arms must be unit variants", DerErrorKind.TypeMismatch)

    def end(mut self) raises DeserializationError:
        pass


@fieldwise_init
struct XmlDeserializer[origin: ImmOrigin](Deserializer):
    var doc: Pointer[Doc, Self.origin]
    var cur: Cursor

    comptime SeqType = XmlSeqDe[Self.origin]
    comptime MapType = XmlMapDe[Self.origin]
    comptime StructType = XmlStructDe[Self.origin]
    comptime TupleType = XmlUnsupportedDe
    comptime EnumType = XmlEnumDe

    # -- cursor resolution -------------------------------------------------
    def _single_node(self) raises DeserializationError -> Int:
        if self.cur.kind == K_ELEMENT or self.cur.kind == K_TEXT:
            return self.cur.node
        if self.cur.kind == K_GROUP:
            var c = self.doc[].first_child(self.cur.node, Int32(self.cur.at))
            if c < 0:
                raise _err("xmojo: missing element <" + String(self.cur.name) + ">", DerErrorKind.MissingField)
            return c
        raise _err(
            "xmojo: attribute @" + String(self.cur.name) + " used where an element was expected",
            DerErrorKind.TypeMismatch,
        )

    def _scalar_text(self) raises DeserializationError -> String:
        if self.cur.kind == K_ATTR:
            ref a = self.doc[].attrs[self.cur.at]
            return self.doc[]._pooled(a.off, a.len)
        return self.doc[].text(self._single_node())

    def _present(self) -> Bool:
        if self.cur.kind == K_GROUP:
            return self.doc[].first_child(self.cur.node, Int32(self.cur.at)) >= 0
        if self.cur.kind == K_TEXT:
            return self.doc[].has_text(self.cur.node)
        return True

    # -- Deserializer ------------------------------------------------------
    def expect_bool(mut self) raises DeserializationError -> Bool:
        var text = self._scalar_text()
        var s = text.strip()
        if s == "true" or s == "1":
            return True
        if s == "false" or s == "0":
            return False
        raise _err("xmojo: not a boolean: " + String(s), DerErrorKind.TypeMismatch)

    def expect_number[DT: DType](mut self) raises DeserializationError -> Scalar[DT]:
        var text = self._scalar_text()
        var s = text.strip()
        try:
            comptime if DT.is_floating_point():
                return Scalar[DT](Float64(s))
            else:
                return Scalar[DT](Int(s))
        except e:
            raise _err("xmojo: not a number: " + String(s), DerErrorKind.TypeMismatch)

    def expect_string(mut self) raises DeserializationError -> String:
        return self._scalar_text()

    def expect_optional[T: Movable & Deinitable](mut self) raises DeserializationError -> Optional[T]:
        if not self._present():
            return Optional[T]()
        return Optional[T](deserialize[T](self))

    def begin_seq(mut self) raises DeserializationError -> Self.SeqType:
        if self.cur.kind == K_GROUP:
            return XmlSeqDe(doc=self.doc, items=self.doc[].children_local(self.cur.node, Int32(self.cur.at)), i=0)
        if self.cur.kind == K_ELEMENT:
            return XmlSeqDe(doc=self.doc, items=[self.cur.node], i=0)
        raise _err("xmojo: attribute @" + String(self.cur.name) + " cannot be a sequence", DerErrorKind.TypeMismatch)

    def begin_map(mut self) raises DeserializationError -> Self.MapType:
        if self.cur.kind == K_ATTRS:
            var n = self.cur.node
            return XmlMapDe(doc=self.doc, node=n, mode=MAP_MODE_ATTRS, keys=self.doc[].attr_names(n), i=0)
        var n = self._single_node()
        return XmlMapDe(doc=self.doc, node=n, mode=MAP_MODE_CHILDREN, keys=self.doc[].child_local_names(n), i=0)

    def begin_struct[T: AnyType](mut self) raises DeserializationError -> Self.StructType:
        var n = self._single_node()
        var fields = List[Cursor]()
        comptime r = reflect[T]
        comptime for i in range(r.field_count()):
            comptime FT = r.field_types()[i]
            comptime if not is_skipped[FT]():
                _bind[T, FT, i](self.doc[], n, fields)
        comptime if conforms_to(T, DenyUnknownFields):
            _deny_unknown(self.doc[], n, fields)
        return XmlStructDe(doc=self.doc, fields=fields^, i=0)

    def begin_tuple[field_count: Int](mut self) raises DeserializationError -> Self.TupleType:
        raise _err("xmojo: tuples are not supported", DerErrorKind.TypeMismatch)

    def begin_enum[T: AnyType, arm_names: List[String]](mut self) raises DeserializationError -> Self.EnumType:
        var text = String(self._scalar_text().strip())
        comptime for i in range(len(arm_names)):
            if materialize[arm_names[i]]() == text:
                return XmlEnumDe(idx=i)
        raise _err(
            "xmojo: enum '" + String(self.cur.name) + "' has no arm '" + text + "'", DerErrorKind.TypeMismatch
        )


def from_xml[T: Movable & Deinitable](s: StringSlice, entities: Dict[String, String] = Dict[String, String]()) raises -> T:
    """Parse XML text and fill `T` from the root element (see module doc for the mapping).
    `entities` as for `parse`."""
    var doc: Doc
    try:
        doc = parse(s, entities)
    except e:
        raise DeserializationError(String(e), DerErrorKind.InvalidValue)
    var d = XmlDeserializer(doc=Pointer(to=doc), cur=Cursor(K_ELEMENT, doc.root(), 0, 0, ""))
    return deserialize[T](d)
