# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# to_xml, the mirror of decode.mojo: a struct becomes an element, its scalar fields attributes
# (a field named `text` the element's text), struct fields and list items child elements named
# after the field, None nothing, a unit enum its arm name, a `Dict[String, V]` named `attrs`
# attributes and any other map child elements keyed by name.
from std.builtin.rebind import downcast
from std.reflection import reflect
from std.utils import Variant
from .field import Field, arm_tag, has_unique_wire_names, is_skipped, static_wire_name

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


struct XmlOut:
    """Where one value goes."""
    var out: Out        # child elements and text
    var attrs: Out      # start tag of the enclosing element, where attributes go
    var name: String    # the field (element or attribute) being written
    var item: Bool      # a list item or map entry: a scalar becomes <name>v</name>

    def __init__(out self, out_: Out, attrs: Out, var name: String, item: Bool):
        self.out = out_
        self.attrs = attrs
        self.name = name^
        self.item = item

    def scalar(mut self, v: StringSlice):
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


trait XmlEncode:
    def xml_encode(self, mut o: XmlOut) raises:
        ...


def encode[T: AnyType, //](v: T, mut o: XmlOut) raises:
    comptime if conforms_to(T, XmlEncode):
        v.xml_encode(o)
    else:
        _encode_struct(v, o)


__extension Bool(XmlEncode):
    def xml_encode(self, mut o: XmlOut) raises:
        o.scalar("true" if self else "false")


__extension String(XmlEncode):
    def xml_encode(self, mut o: XmlOut) raises:
        o.scalar(self)


__extension SIMD(XmlEncode):
    def xml_encode(self, mut o: XmlOut) raises:
        comptime assert Self.length == 1, "xmojo: only scalar SIMD fields"
        comptime if Self.dtype == DType.bool:
            o.scalar("true" if rebind[Scalar[DType.bool]](self) else "false")
        else:
            o.scalar(String(self))


__extension Optional(XmlEncode):
    def xml_encode(self, mut o: XmlOut) raises:
        if self:
            encode(self.value(), o)


__extension List(XmlEncode):
    def xml_encode(self, mut o: XmlOut) raises:
        for ref v in self:
            var sub = XmlOut(o.out, o.attrs, o.name.copy(), True)
            encode(v, sub)


__extension Dict(XmlEncode):
    def xml_encode(self, mut o: XmlOut) raises:
        comptime assert reflect[Self.K].name() == reflect[String].name(), "xmojo: map keys must be String"
        var as_attrs = o.name == "attrs"
        for entry in self.items():
            var key = String()
            _escape[False](key, rebind[String](entry.key))
            var sub = XmlOut(o.out, o.attrs, key^, not as_attrs)
            encode(entry.value, sub)


__extension Variant(XmlEncode):
    def xml_encode(self, mut o: XmlOut) raises:
        comptime for i in range(Self.Ts.length):
            if self.isa[Self.Ts[i]]():
                o.scalar(arm_tag[Self.Ts[i]]())   # unit arms only: the name is the whole value


__extension Field(XmlEncode):
    def xml_encode(self, mut o: XmlOut) raises:
        encode(self.value, o)


def _encode_struct[T: AnyType](v: T, mut o: XmlOut) raises:
    comptime r = reflect[T]
    comptime assert r.is_struct(), "xmojo: to_xml needs a struct"
    comptime assert has_unique_wire_names[T](), "xmojo: two fields have the same wire name"
    var tag = "<" + o.name   # "<name" plus attributes so far
    var body = String()      # child elements and text
    comptime for i in range(r.field_count()):
        comptime FT = r.field_types()[i]
        comptime if not is_skipped[FT]():
            var sub = XmlOut(_to(body), _to(tag), String(static_wire_name[T, FT, r.field_names()[i]]()), False)
            encode(r.field_ref[i](v), sub)
    ref out = o.out[]   # appended piecewise: `">" + body + ...` would copy the body once more
    out += tag
    if body.byte_length() == 0:
        out += "/>"
        return
    out.reserve_bytes(out.byte_length() + body.byte_length() + o.name.byte_length() + 4)
    out += ">"
    out += body
    out += "</"
    out += o.name
    out += ">"


def to_xml[T: AnyType](v: T, root: StringSlice) raises -> String:
    """Serialize `v` (a struct) as an XML element named `root`; `from_xml[T]` reads it back."""
    var out = String()
    var unused = String()
    var o = XmlOut(_to(out), _to(unused), String(root), False)
    encode(v, o)
    return out^
