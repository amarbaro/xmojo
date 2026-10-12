# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Arena DOM: one fixed-size record per element in a flat list. Names and namespace URIs are
# interned; decoded text and attribute values live in one byte pool. Whitespace-only text is
# dropped by the tokenizer unless xml:space="preserve" is in scope.
from .tokenizer import Tokenizer, Token, TokenKind, Attr, make_error, decode_into, check_decl, qname_colon
from .error import XmlError

comptime NONE: Int32 = -1
comptime MAX_BYTES = 0x7FFF_FFFF   # node indices and pool offsets are Int32
comptime COLON: UInt8 = 58
comptime XML_NS = "http://www.w3.org/XML/1998/namespace"   # the predeclared `xml:` prefix
comptime XMLNS_NS = "http://www.w3.org/2000/xmlns/"        # namespace of xmlns:* declarations


@fieldwise_init
struct Node(ImplicitlyCopyable):
    """One element. `name` indexes `Doc.names`, `ns` indexes `Doc.uris`, text is a byte range
    of `Doc.pool`, attributes a range of `Doc.attrs`. Read it through `Doc`."""
    var name: Int32          # qualified name as written
    var ns: Int32            # resolved namespace URI, 0 = ""
    var parent: Int32        # NONE for the root
    var first_child: Int32
    var next_sibling: Int32
    var attr0: Int32
    var nattr: Int32
    var text_off: Int32      # concatenated text + CDATA children
    var text_len: Int32


@fieldwise_init
struct AttrRec(ImplicitlyCopyable):
    var name: Int32          # index into Doc.names
    var ns: Int32            # resolved namespace URI, 0 = "" (unprefixed attributes have none)
    var off: Int32           # decoded value, byte range of Doc.pool
    var len: Int32


struct Doc(Movable):
    var nodes: List[Node]
    var attrs: List[AttrRec]
    var names: List[String]          # interned element and attribute names
    var local_of: List[Int32]        # per name id: id of its local part (itself if unprefixed)
    var name_ids: Dict[String, Int]
    var uris: List[String]           # interned namespace URIs, 0 = ""
    var pool: List[UInt8]            # decoded text and attribute values, UTF-8

    def __init__(out self):
        self.nodes = List[Node]()
        self.attrs = List[AttrRec]()
        self.names = List[String]()
        self.local_of = List[Int32]()
        self.name_ids = Dict[String, Int]()
        self.uris = [String(""), String(XML_NS), String(XMLNS_NS)]
        self.pool = List[UInt8]()

    def __len__(self) -> Int:
        return len(self.nodes)

    def root(self) -> Int:
        return 0

    def _intern(mut self, var s: String) -> Int32:
        var id = self.name_ids.get(s)
        if id:
            return Int32(id.value())
        var n = len(self.names)
        var c = s.find(":")
        self.name_ids[s.copy()] = n
        self.names.append(s^)
        self.local_of.append(Int32(n))
        if c >= 0:
            var local = self._intern(String(self.names[n][byte = c + 1 :]))   # grows local_of
            self.local_of[n] = local
        return Int32(n)

    def _id(self, s: String) -> Int32:
        """Interned id of `s`, NONE if no element or attribute has that name."""
        var id = self.name_ids.get(s)
        return Int32(id.value()) if id else NONE

    def _pooled(self, off: Int32, n: Int32) -> String:
        return String(unsafe_from_utf8=Span(self.pool)[Int(off) : Int(off + n)])

    def name(self, i: Int) -> String:
        return self.names[Int(self.nodes[i].name)].copy()

    def local_name(self, i: Int) -> String:
        return self.names[Int(self.local_of[Int(self.nodes[i].name)])].copy()

    def prefix(self, i: Int) -> String:
        ref q = self.names[Int(self.nodes[i].name)]
        var c = q.find(":")
        return String(q[byte=0:c]) if c >= 0 else String("")

    def ns(self, i: Int) -> String:
        return self.uris[Int(self.nodes[i].ns)].copy()

    def text(self, i: Int) -> String:
        return self._pooled(self.nodes[i].text_off, self.nodes[i].text_len)

    def has_text(self, i: Int) -> Bool:
        return self.nodes[i].text_len > 0

    def parent(self, i: Int) -> Int:
        return Int(self.nodes[i].parent)

    def children(self, i: Int) -> List[Int]:
        var out = List[Int]()
        var c = self.nodes[i].first_child
        while c != NONE:
            out.append(Int(c))
            c = self.nodes[Int(c)].next_sibling
        return out^

    def attr(self, i: Int, name: String) -> Optional[String]:
        var id = self._id(name)
        var a0 = Int(self.nodes[i].attr0)
        for k in range(a0, a0 + Int(self.nodes[i].nattr)):
            if self.attrs[k].name == id:
                return self._pooled(self.attrs[k].off, self.attrs[k].len)
        return None

    def attr_ns(self, i: Int, ns: Optional[String], local: String) -> Optional[String]:
        """Value of the attribute with local name `local` and, if `ns` is given, that resolved
        namespace URI (unprefixed attributes have namespace "")."""
        var id = self._id(local)
        var a0 = Int(self.nodes[i].attr0)
        for k in range(a0, a0 + Int(self.nodes[i].nattr)):
            ref a = self.attrs[k]
            if self.local_of[Int(a.name)] == id and (not ns or self.uris[Int(a.ns)] == ns.value()):
                return self._pooled(a.off, a.len)
        return None

    def attr_names(self, i: Int) -> List[String]:
        var out = List[String]()
        var a0 = Int(self.nodes[i].attr0)
        for k in range(a0, a0 + Int(self.nodes[i].nattr)):
            out.append(self.names[Int(self.attrs[k].name)].copy())
        return out^

    def attr_index(self, i: Int, local: Int32) -> Int:
        """Index into `attrs` of element i's first attribute with that local-name id, xmlns:*
        declarations excluded; -1 if none."""
        var a0 = Int(self.nodes[i].attr0)
        for k in range(a0, a0 + Int(self.nodes[i].nattr)):
            if self.local_of[Int(self.attrs[k].name)] == local and self.attrs[k].ns != 2:
                return k
        return -1

    def first_child(self, i: Int, local: Int32) -> Int:
        """First child of element i with that local-name id, -1 if none."""
        var c = self.nodes[i].first_child
        while c != NONE and local != NONE:
            if self.local_of[Int(self.nodes[Int(c)].name)] == local:
                return Int(c)
            c = self.nodes[Int(c)].next_sibling
        return -1

    def children_local(self, i: Int, local: Int32) -> List[Int]:
        """Children of element i with that local-name id."""
        var out = List[Int]()
        var c = self.first_child(i, local)
        while c >= 0:
            out.append(c)
            c = Int(self.nodes[c].next_sibling)
            while c >= 0 and self.local_of[Int(self.nodes[c].name)] != local:
                c = Int(self.nodes[c].next_sibling)
        return out^

    def children_named(self, idx: Int, local: String) -> List[Int]:
        return self.children_ns(idx, Optional[String](), local)

    def children_ns(self, idx: Int, ns: Optional[String], local: String) -> List[Int]:
        """Children with local name `local` and, if `ns` is given, that resolved URI."""
        var out = List[Int]()
        var id = self._id(local)
        if id == NONE:
            return out^
        var c = self.nodes[idx].first_child
        while c != NONE:
            ref n = self.nodes[Int(c)]
            if self.local_of[Int(n.name)] == id and (not ns or self.uris[Int(n.ns)] == ns.value()):
                out.append(Int(c))
            c = n.next_sibling
        return out^

    def child_local_names(self, idx: Int) -> List[String]:
        """Distinct local names of child elements, first-appearance order."""
        var ids = List[Int32]()
        var c = self.nodes[idx].first_child
        while c != NONE:
            var l = self.local_of[Int(self.nodes[Int(c)].name)]
            if l not in ids:
                ids.append(l)
            c = self.nodes[Int(c)].next_sibling
        var out = List[String]()
        for l in ids:
            out.append(self.names[Int(l)].copy())
        return out^


def _str(src: Span[UInt8, _], a: Int, b: Int) -> String:
    return String(unsafe_from_utf8=src[a:b])


def _xmlns_prefix(src: Span[UInt8, _], a: Attr) -> Optional[String]:
    """The prefix an `xmlns`/`xmlns:p` attribute declares ("" for the default
    namespace), None for any other attribute."""
    var n = a.name_e - a.name_s
    if n < 5 or _str(src, a.name_s, a.name_s + 5) != "xmlns":
        return None
    if n == 5:
        return String("")
    if src[a.name_s + 5] != COLON:
        return None
    return _str(src, a.name_s + 6, a.name_e)


def _with_tag(e: XmlError, doc: Doc, stack: List[Int]) -> XmlError:
    """Fill in the nearest still-open element as `tag`, only on the error path."""
    var tag = doc.name(stack[len(stack) - 1]) if len(stack) > 0 else String("")
    return XmlError(e.message.copy(), e.line, e.col, tag^)


def _decode[attr: Bool = False, cdata: Bool = False](
    src: Span[UInt8, _], raw: Span[UInt8, _], at: Int, mut out: List[UInt8], entities: Dict[String, String]
) raises XmlError:
    try:
        decode_into[attr, cdata](raw, out, entities)
    except e:
        raise make_error(src, at, "", String(e))


# Prefixed attributes are rare: resolved out of line, and errors are returned rather than raised
# so the attribute loop carries no landing pad.
@no_inline
def _attr_ns_id(scope: Dict[String, Int], src: Span[UInt8, _], a: Attr, colon: Int) -> Int:
    """Namespace id of a prefixed attribute (2 for xmlns:*), -1 undeclared, -2 not a QName."""
    if colon == -2:
        return -2
    var p = _str(src, a.name_s, colon)
    if p == "xmlns":
        return 2
    return scope.get(p).or_else(-1)


@no_inline
def _attr_ns_err(src: Span[UInt8, _], a: Attr, colon: Int, at: Int) -> XmlError:
    if colon == -2:
        return make_error(src, at, "", "malformed qualified attribute name " + _str(src, a.name_s, a.name_e))
    return make_error(src, at, "", "undeclared namespace prefix '" + _str(src, a.name_s, colon) + "'")


def parse(s: StringSlice, entities: Dict[String, String] = Dict[String, String]()) raises XmlError -> Doc:
    """Parse UTF-8 XML text into a `Doc`. `entities` adds named entities beyond XML's five
    (`html_entities()` for HTML's), consulted only for an otherwise unknown `&name;`."""
    var doc = Doc()
    var tok = Tokenizer(s)
    var src = tok.src
    if len(src) > MAX_BYTES:
        raise make_error(src, 0, "", "input over 2 GiB is not supported")
    if len(src) >= 3 and src[0] == 0xEF and src[1] == 0xBB and src[2] == 0xBF:
        tok.pos = 3   # UTF-8 byte order mark
    check_decl(src[tok.pos :])
    var stack = List[Int]()
    var lasts = List[Int32]()  # last child so far of each open element, parallel to `stack`
    var keeps = List[Bool]()   # xml:space="preserve" in effect, parallel to `stack`
    var starts = List[Int]()   # byte offset of each open element's start tag
    var scratch = List[UInt8]()
    # Namespace scopes (prefix -> uri id) live in an arena; `scope_idx` (parallel to
    # `stack`) names the entry in effect for each open element. Index 0 is the implicit
    # empty scope. An element that declares nothing shares its parent's index; only a
    # declaring element allocates a new entry (parent's scope, copied, plus its own).
    var scope_arena = List[Dict[String, Int]]()
    scope_arena.append({"xml": 1})
    var scope_idx = List[Int]()
    while True:
        var t: Token
        try:
            t = tok.next()
        except e:
            raise _with_tag(e, doc, stack)
        if t.kind == TokenKind.EOF:
            break
        if t.kind == TokenKind.START:
            if len(stack) == 0 and len(doc.nodes) > 0:
                raise make_error(src, t.start, "", "content after the root element")
            var parent = stack[len(stack) - 1] if len(stack) > 0 else -1
            var idx = len(doc.nodes)
            var this_scope_i = scope_idx[len(scope_idx) - 1] if len(scope_idx) > 0 else 0
            var declares_ns = False
            for a in tok.attrs:
                if _xmlns_prefix(src, a):
                    declares_ns = True
                    break
            if declares_ns:
                var scope = scope_arena[this_scope_i].copy()
                for a in tok.attrs:
                    var p = _xmlns_prefix(src, a)
                    if p:
                        scratch.clear()
                        try:
                            _decode[True](src, src[a.val_s : a.val_e], t.start, scratch, entities)
                        except e:
                            raise _with_tag(e, doc, stack)
                        var uri = String(unsafe_from_utf8=Span(scratch))
                        var uri_id = len(doc.uris)
                        for u in range(len(doc.uris)):
                            if doc.uris[u] == uri:
                                uri_id = u
                                break
                        if uri_id == len(doc.uris):
                            doc.uris.append(uri^)
                        scope[p.value()] = uri_id
                this_scope_i = len(scope_arena)
                scope_arena.append(scope^)
            var colon = qname_colon(src, t.s, t.e)
            if colon == -2:
                raise _with_tag(make_error(src, t.start, "", "malformed qualified name <" + _str(src, t.s, t.e) + ">"), doc, stack)
            var prefix = _str(src, t.s, colon) if colon >= 0 else String("")
            # Scope 0 binds only `xml:`, so an unprefixed element there skips the lookup.
            var ns_id = scope_arena[this_scope_i].get(prefix) if colon >= 0 or this_scope_i != 0 else Optional[Int]()
            if not ns_id and colon >= 0:
                raise _with_tag(make_error(src, t.start, "", "undeclared namespace prefix '" + prefix + "'"), doc, stack)
            var name_id = doc._intern(_str(src, t.s, t.e))
            var attr0 = len(doc.attrs)
            var keep = keeps[len(keeps) - 1] if len(keeps) > 0 else False
            for a in tok.attrs:
                var off = len(doc.pool)
                try:
                    _decode[True](src, src[a.val_s : a.val_e], t.start, doc.pool, entities)
                except e:
                    raise _with_tag(e, doc, stack)
                var vlen = len(doc.pool) - off
                var ans = 0
                var acolon = qname_colon(src, a.name_s, a.name_e)
                if acolon != -1:
                    ans = _attr_ns_id(scope_arena[this_scope_i], src, a, acolon)
                    if ans < 0:
                        raise _with_tag(_attr_ns_err(src, a, acolon, t.start), doc, stack)
                    if ans == 1 and _str(src, a.name_s, a.name_e) == "xml:space":
                        var v = _str(doc.pool, off, off + vlen)
                        keep = v == "preserve" or (keep and v != "default")
                var aname = doc._intern(_str(src, a.name_s, a.name_e))
                doc.attrs.append(AttrRec(aname, Int32(ans), Int32(off), Int32(vlen)))
            doc.nodes.append(
                Node(
                    name_id, Int32(ns_id.or_else(0)), Int32(parent), NONE, NONE,
                    Int32(attr0), Int32(len(tok.attrs)), 0, 0,
                )
            )
            if parent >= 0:
                var last = lasts[len(lasts) - 1]
                if last == NONE:
                    doc.nodes[parent].first_child = Int32(idx)
                else:
                    doc.nodes[Int(last)].next_sibling = Int32(idx)
                lasts[len(lasts) - 1] = Int32(idx)
            if not t.self_closing:
                stack.append(idx)
                lasts.append(NONE)
                keeps.append(keep)
                tok.keep_space = keep
                starts.append(t.start)
                scope_idx.append(this_scope_i)
        elif t.kind == TokenKind.END:
            var end_name = _str(src, t.s, t.e)
            if len(stack) == 0:
                raise make_error(src, t.start, "", "stray end tag </" + end_name + ">")
            var top = stack.pop()
            _ = lasts.pop()
            _ = keeps.pop()
            tok.keep_space = keeps[len(keeps) - 1] if len(keeps) > 0 else False
            _ = starts.pop()
            _ = scope_idx.pop()
            ref open_name = doc.names[Int(doc.nodes[top].name)]
            if open_name != end_name:
                raise make_error(
                    src, t.start, open_name.copy(),
                    "mismatched end tag </" + end_name + ">, open <" + open_name + ">",
                )
        else:
            var raw = src[t.s : t.e]
            if len(stack) == 0:
                raise make_error(src, t.start, "", "text outside the root element")
            var k = stack[len(stack) - 1]
            var off = Int(doc.nodes[k].text_off)
            var n = Int(doc.nodes[k].text_len)
            if n == 0:
                off = len(doc.pool)
            elif off + n != len(doc.pool):
                # Text resumes after a child's bytes: move it to the end to keep it contiguous.
                var moved = len(doc.pool)
                for q in range(off, off + n):
                    doc.pool.append(doc.pool[q])
                off = moved
            try:
                if t.cdata:
                    _decode[cdata=True](src, raw, t.start, doc.pool, entities)
                else:
                    _decode(src, raw, t.start, doc.pool, entities)
            except e:
                raise _with_tag(e, doc, stack)
            doc.nodes[k].text_off = Int32(off)
            doc.nodes[k].text_len = Int32(len(doc.pool) - off)
    if len(stack) != 0:
        var top = stack[len(stack) - 1]
        raise make_error(src, starts[len(starts) - 1], doc.name(top), "unclosed element <" + doc.name(top) + ">")
    if len(doc.nodes) == 0:
        raise make_error(src, 0, "", "no root element")
    if len(doc.pool) > MAX_BYTES:   # an entity map can expand text past what Int32 offsets reach
        raise make_error(src, 0, "", "decoded text over 2 GiB is not supported")
    return doc^
