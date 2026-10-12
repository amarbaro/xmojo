# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# emberserde format writing XML, the mirror of deserializer.mojo: a struct becomes an element,
# its scalar fields attributes (a field named `text` the element's text), struct fields and list
# items child elements named after the field, None nothing, a unit enum its arm name, a
# `Dict[String, V]` named `attrs` attributes and any other map child elements keyed by name.
from emberserde import (
    Serializer,
    SeqSerState,
    MapSerState,
    StructSerState,
    TupleSerState,
    EnumSerState,
    SerializationError,
    SerErrorKind,
    serialize,
)

comptime Out = Pointer[String, MutUntrackedOrigin]   # every target outlives the call that writes it


def _to(mut s: String) -> Out:
    return Pointer(to=s).unsafe_origin_cast[MutUntrackedOrigin]()


def _escape[attr: Bool](mut out: String, s: StringSlice):
    """Append `s` escaped so that parsing it back gives `s`: & < > always, " in attributes,
    and the characters XML would otherwise normalize (CR; tab and LF in attributes)."""
    var b = s.as_bytes()
    var start = 0
    for i in range(len(b)):
        var c = b[i]
        var rep: StaticString
        if c == 38:
            rep = "&amp;"
        elif c == 60:
            rep = "&lt;"
        elif c == 62:
            rep = "&gt;"
        elif c == 13:
            rep = "&#13;"
        elif attr and c == 34:
            rep = "&quot;"
        elif attr and c == 9:
            rep = "&#9;"
        elif attr and c == 10:
            rep = "&#10;"
        else:
            continue
        out += StringSlice(unsafe_from_utf8=b[start:i])
        out += rep
        start = i + 1
    out += StringSlice(unsafe_from_utf8=b[start:])


struct XmlSerializer(Serializer):
    var out: Out        # where child elements and text go
    var attrs: Out      # start tag of the enclosing element, where attributes go
    var name: String    # the field (element or attribute) being written
    var item: Bool      # a list item or map entry: a scalar becomes <name>v</name>

    comptime StructType = XmlStructSer
    comptime SeqType = XmlSeqSer
    comptime MapType = XmlMapSer
    comptime TupleType = XmlTupleSer
    comptime EnumType = XmlEnumSer

    def __init__(out self, out_: Out, attrs: Out, var name: String, item: Bool):
        self.out = out_
        self.attrs = attrs
        self.name = name^
        self.item = item

    def _scalar(mut self, v: StringSlice):
        if self.item:
            self.out[] += "<" + self.name + ">"
            _escape[False](self.out[], v)
            self.out[] += "</" + self.name + ">"
        elif self.name == "text":
            _escape[False](self.out[], v)
        else:
            self.attrs[] += " " + self.name + '="'
            _escape[True](self.attrs[], v)
            self.attrs[] += '"'

    def serialize_bool(mut self, v: Bool) raises SerializationError:
        self._scalar("true" if v else "false")

    def serialize_number[dt: DType, //](mut self, v: Scalar[dt]) raises SerializationError:
        self._scalar(String(v))

    def serialize_string(mut self, v: StringSlice) raises SerializationError:
        self._scalar(v)

    def serialize_none(mut self) raises SerializationError:
        pass

    def begin_seq(mut self, size_hint: Optional[Int] = None) raises SerializationError -> XmlSeqSer:
        return XmlSeqSer(self.out, self.attrs, self.name.copy())

    def begin_map(mut self, size_hint: Optional[Int] = None) raises SerializationError -> XmlMapSer:
        return XmlMapSer(self.out, self.attrs, self.name == "attrs", "")

    def begin_struct[T: AnyType](mut self, field_count: Int) raises SerializationError -> XmlStructSer:
        return XmlStructSer(self.out, "<" + self.name, "", self.name.copy())

    def begin_tuple[field_count: Int](mut self) raises SerializationError -> XmlTupleSer:
        raise SerializationError("xmojo: tuples are not supported", SerErrorKind.InvalidValue)

    def begin_enum[T: AnyType, variant: String](mut self, idx: UInt32) raises SerializationError -> XmlEnumSer:
        self._scalar(variant)
        return XmlEnumSer()


@fieldwise_init
struct XmlStructSer(StructSerState):
    var out: Out
    var tag: String     # "<name" plus attributes so far
    var body: String    # child elements and text
    var name: String

    def serialize_field[T: AnyType, idx: Int](mut self, field_name: StringSlice, v: Some[AnyType]) raises SerializationError:
        var s = XmlSerializer(_to(self.body), _to(self.tag), String(field_name), False)
        serialize(v, s)

    def end(mut self) raises SerializationError:
        ref out = self.out[]   # appended piecewise: `">" + body + ...` would copy the body once more
        out += self.tag
        if self.body.byte_length() == 0:
            out += "/>"
            return
        out.reserve_bytes(out.byte_length() + self.body.byte_length() + self.name.byte_length() + 4)
        out += ">"
        out += self.body
        out += "</"
        out += self.name
        out += ">"


@fieldwise_init
struct XmlSeqSer(SeqSerState):
    var out: Out
    var attrs: Out
    var name: String

    def serialize_element(mut self, v: Some[AnyType]) raises SerializationError:
        var s = XmlSerializer(self.out, self.attrs, self.name.copy(), True)
        serialize(v, s)

    def end(mut self) raises SerializationError:
        pass


@fieldwise_init
struct XmlMapSer(MapSerState):
    var out: Out
    var attrs: Out
    var as_attrs: Bool  # the field named `attrs`: entries become attributes
    var key: String

    def serialize_key(mut self, k: Some[AnyType]) raises SerializationError:
        var cap = XmlSerializer(_to(self.key), _to(self.key), "text", False)
        self.key = ""
        serialize(k, cap)

    def serialize_value(mut self, v: Some[AnyType]) raises SerializationError:
        var s = XmlSerializer(self.out, self.attrs, self.key.copy(), not self.as_attrs)
        serialize(v, s)

    def end(mut self) raises SerializationError:
        pass


struct XmlTupleSer(TupleSerState):
    def serialize_element(mut self, v: Some[AnyType]) raises SerializationError:
        pass

    def end(mut self) raises SerializationError:
        pass


@fieldwise_init
struct XmlEnumSer(EnumSerState):
    def serialize_payload(mut self, v: Some[AnyType]) raises SerializationError:
        pass   # unit variants only, as in from_xml: the arm name is the whole value

    def end(mut self) raises SerializationError:
        pass


def to_xml[T: AnyType](v: T, root: StringSlice) raises SerializationError -> String:
    """Serialize `v` (a struct) as an XML element named `root`; `from_xml[T]` reads it back."""
    var out = String()
    var unused = String()
    var s = XmlSerializer(_to(out), _to(unused), String(root), False)
    serialize(v, s)
    return out^
