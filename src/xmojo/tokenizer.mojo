# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Byte-level pull tokenizer. Atom-first scope (PLAN.md): elements, attributes, text,
# CDATA, predefined + numeric entities; skips XML decl, PIs, comments, DOCTYPE. No validation.
from .error import XmlError


@fieldwise_init
struct Attr(ImplicitlyCopyable):
    """One attribute of the current start tag, as raw byte ranges of the source
    (value still entity-encoded, quotes excluded)."""
    var name_s: Int
    var name_e: Int
    var val_s: Int
    var val_e: Int


@fieldwise_init
struct TokenKind(Equatable, ImplicitlyCopyable, Writable):
    var v: Int
    comptime EOF = TokenKind(0)
    comptime START = TokenKind(1)
    comptime END = TokenKind(2)
    comptime TEXT = TokenKind(3)

    def __eq__(self, other: Self) -> Bool:
        return self.v == other.v

    def __ne__(self, other: Self) -> Bool:
        return self.v != other.v

    def write_to(self, mut writer: Some[Writer]):
        writer.write(self.v)


@fieldwise_init
struct Token(ImplicitlyCopyable):
    """Byte ranges into the source, no copies. START/END: `s:e` is the qualified name;
    START's attributes are in `Tokenizer.attrs` until the next call. TEXT: `s:e` is the
    raw run, entity-encoded unless `cdata`."""
    var kind: TokenKind
    var s: Int
    var e: Int
    var self_closing: Bool
    var cdata: Bool
    var start: Int              # byte offset where this token began


comptime LT: UInt8 = 60  # LT
comptime GT: UInt8 = 62
comptime SLASH: UInt8 = 47
comptime EQ: UInt8 = 61
comptime AMP: UInt8 = 38
comptime SEMI: UInt8 = 59
comptime DQ: UInt8 = 34
comptime SQ: UInt8 = 39


def _is_space(b: UInt8) -> Bool:
    return b == 32 or b == 10 or b == 9 or b == 13


def _is_digit(b: UInt8) -> Bool:
    return b >= 48 and b <= 57


def _is_name_byte(b: UInt8) -> Bool:
    """XML NameChar: exact for ASCII, any byte of a non-ASCII UTF-8 sequence accepted."""
    return b >= 0x80 or (b | 0x20 >= 97 and b | 0x20 <= 122) or _is_digit(b) or b == 95 or b == 58 or b == 45 or b == 46


def _is_name_start(b: UInt8) -> Bool:
    return _is_name_byte(b) and not _is_digit(b) and b != 45 and b != 46


def qname_colon(src: Span[UInt8, _], s: Int, e: Int) -> Int:
    """Offset of the prefix colon in the name src[s:e], -1 if unprefixed, -2 if it is not a
    QName (empty prefix or local part, a second colon, a local part with a bad first byte)."""
    var colon = -1
    for k in range(s, e):
        if src[k] == 58:
            if colon >= 0:
                return -2
            colon = k
    if colon >= 0 and (colon == s or colon + 1 == e or not _is_name_start(src[colon + 1])):
        return -2
    return colon


def _bytes_to_string(bytes: Span[UInt8, _]) -> String:
    return String(from_utf8_lossy=bytes)


@fieldwise_init
struct Pos(Copyable, Movable):
    var line: Int
    var col: Int


def line_col(src: Span[UInt8, _], at: Int) -> Pos:
    """1-based line/col of byte offset `at` (bytes, not codepoints)."""
    var line = 1
    var col = 1
    var n = at if at < len(src) else len(src)
    for i in range(n):
        if src[i] == 10:
            line += 1
            col = 1
        else:
            col += 1
    return Pos(line, col)


def make_error(src: Span[UInt8, _], at: Int, tag: String, var msg: String) -> XmlError:
    var p = line_col(src, at)
    return XmlError(msg^, p.line, p.col, tag.copy())


def _parse_uint(digits: Span[UInt8, _], base: Int) raises -> UInt32:
    var v: UInt32 = 0
    if len(digits) == 0:
        raise Error("empty numeric entity")
    for b in digits:
        var d: Int
        if b >= 48 and b <= 57:
            d = Int(b) - 48
        elif b >= 97 and b <= 102:
            d = Int(b) - 87
        elif b >= 65 and b <= 70:
            d = Int(b) - 55
        else:
            raise Error("bad digit in numeric entity")
        if d >= base:
            raise Error("bad digit in numeric entity")
        v = v * UInt32(base) + UInt32(d)
    return v


comptime LF: UInt8 = 10
comptime CR: UInt8 = 13
comptime TAB: UInt8 = 9
comptime SPACE: UInt8 = 32


def decode_into[attr: Bool = False, cdata: Bool = False](
    raw: Span[UInt8, _], mut out: List[UInt8], entities: Dict[String, String]
) raises:
    """Append `raw` to `out` as XML 1.0 normalizes it: CR LF and lone CR become LF (2.11); in an
    attribute value literal tab, LF and CR become a space (3.3.3); outside CDATA, &amp; &lt; &gt;
    &quot; &apos; &#N; &#xH; are decoded, and any other `&name;` found in `entities`. Unknown
    entities, a bare '&' and references to characters XML does not allow raise."""
    var n = len(raw)
    var start = 0
    var i = 0
    while i < n:
        var b = raw[i]
        if b == CR or (attr and (b == TAB or b == LF)):
            out.extend(raw[start:i])
            out.append(SPACE if attr else LF)
            i += 2 if b == CR and i + 1 < n and raw[i + 1] == LF else 1
            start = i
            continue
        if cdata or b != AMP:
            i += 1
            continue
        var j = i + 1
        while j < n and raw[j] != SEMI and j - i < 32:
            j += 1
        if j >= n or raw[j] != SEMI:
            raise Error("bare '&' (write &amp;)")
        out.extend(raw[start:i])
        var ent_bytes = raw[i + 1 : j]
        var ent = _bytes_to_string(ent_bytes)
        if ent == "amp":
            out.append(AMP)
        elif ent == "lt":
            out.append(LT)
        elif ent == "gt":
            out.append(GT)
        elif ent == "quot":
            out.append(DQ)
        elif ent == "apos":
            out.append(SQ)
        elif ent.startswith("#"):
            var hex = ent.startswith("#x")
            var c = _parse_uint(ent_bytes[2 if hex else 1 :], 16 if hex else 10)
            var cp = Codepoint.from_u32(c)
            if not cp or (c < 32 and c != 9 and c != 10 and c != 13) or c == 0xFFFE or c == 0xFFFF:
                raise Error("reference to a character XML does not allow: &" + ent + ";")
            out.extend(String(cp.value()).as_bytes())
        else:
            var v = entities.get(ent)
            if not v:
                raise Error("unknown entity &" + ent + ";")
            out.extend(v.value().as_bytes())
        i = j + 1
        start = i
    out.extend(raw[start:n])


def _bad_decl(src: Span[UInt8, _]) -> XmlError:
    return make_error(src, 0, "", "malformed XML declaration")


def check_decl(src: Span[UInt8, _]) raises XmlError:
    """An XML declaration (`<?xml` and a space at offset 0) holds version="1.x", then optionally
    encoding and standalone, in that order, each quoted and preceded by whitespace."""
    if len(src) < 6 or _bytes_to_string(src[0:5]) != "<?xml" or not _is_space(src[5]):
        return
    var d = _bytes_to_string(src[5:])
    var end = d.find("?>")
    if end < 0:
        raise _bad_decl(src)
    var rest = String(d[byte=0:end])
    var names: List[String] = ["version", "encoding", "standalone"]
    var k = 0
    while True:
        var trimmed = String(rest.lstrip())
        if trimmed == "":
            break
        if trimmed.byte_length() == rest.byte_length():
            raise _bad_decl(src)
        while k < 3 and not trimmed.startswith(names[k]):
            k += 1
        if k == 3:
            raise _bad_decl(src)
        rest = String(String(trimmed[byte = names[k].byte_length() :]).lstrip())
        if not rest.startswith("="):
            raise _bad_decl(src)
        rest = String(String(rest[byte=1:]).lstrip())
        var q = String(rest[byte=0:1])
        var close = rest.find(q, 1) if q == "'" or q == '"' else -1
        if close < 0:
            raise _bad_decl(src)
        var v = String(rest[byte=1:close])
        if k == 0 and not (v.startswith("1.") and v.byte_length() > 2 and v[byte=2:].is_ascii_digit()):
            raise _bad_decl(src)
        if k == 2 and v != "yes" and v != "no":
            raise _bad_decl(src)
        var enc = v.lower()
        if k == 1 and enc != "utf-8" and enc != "us-ascii":
            raise make_error(src, 0, "", "unsupported encoding '" + v + "' (transcode to UTF-8 first)")
        if k > 0 and names[0] != "":
            raise _bad_decl(src)   # version missing
        names[0] = ""
        var tail = String(rest[byte = close + 1 :])
        rest = tail^
        k += 1
    if names[0] != "":
        raise _bad_decl(src)


def bytes_eq(src: Span[UInt8, _], a: Int, b: Int, c: Int, d: Int) -> Bool:
    """True when src[a:b] == src[c:d]."""
    if b - a != d - c:
        return False
    for k in range(b - a):
        if src[a + k] != src[c + k]:
            return False
    return True


struct Tokenizer[origin: ImmOrigin](Movable):
    var src: Span[UInt8, Self.origin]
    var pos: Int
    var attrs: List[Attr]       # current start tag's attributes, reused across tags
    var keep_space: Bool        # emit whitespace-only text (set by the parser under xml:space="preserve")

    def __init__(out self, s: StringSlice[Self.origin]):
        self.src = s.as_bytes()
        self.pos = 0
        self.attrs = List[Attr]()
        self.keep_space = False

    def _peek(self, off: Int = 0) -> UInt8:
        var p = self.pos + off
        return self.src[p] if p < len(self.src) else 0

    def _starts_with(self, lit: StaticString) -> Bool:
        var b = lit.as_bytes()
        if self.pos + len(b) > len(self.src):
            return False
        for k in range(len(b)):
            if self.src[self.pos + k] != b[k]:
                return False
        return True

    def _skip_past(mut self, lit: StaticString, start: Int) raises XmlError:
        var b = lit.as_bytes()
        while self.pos + len(b) <= len(self.src):
            var ok = True
            for k in range(len(b)):
                if self.src[self.pos + k] != b[k]:
                    ok = False
                    break
            if ok:
                self.pos += len(b)
                return
            self.pos += 1
        raise make_error(self.src, start, "", "unterminated construct, expected " + String(lit))

    def _skip_name(mut self):
        while self.pos < len(self.src) and _is_name_byte(self.src[self.pos]):
            self.pos += 1

    def _skip_space(mut self):
        while self.pos < len(self.src) and _is_space(self.src[self.pos]):
            self.pos += 1

    def _str(self, a: Int, b: Int) -> String:
        return _bytes_to_string(self.src[a:b])

    def next(mut self) raises XmlError -> Token:
        """Next token; whitespace-only text between tags is dropped."""
        while True:
            var start = self.pos
            if self.pos >= len(self.src):
                return Token(TokenKind.EOF, start, start, False, False, start)
            if self._peek() != LT:
                # text run up to next '<'
                var s = self.pos
                var all_space = True
                while self.pos < len(self.src) and self.src[self.pos] != LT:
                    if not _is_space(self.src[self.pos]):
                        all_space = False
                    self.pos += 1
                if all_space and not self.keep_space:
                    continue
                return Token(TokenKind.TEXT, s, self.pos, False, False, start)
            # '<'
            if self._starts_with("<![CDATA["):
                self.pos += 9
                var s = self.pos
                self._skip_past("]]>", start)
                return Token(TokenKind.TEXT, s, self.pos - 3, False, True, start)
            if self._starts_with("<!--"):
                self._skip_past("-->", start)
                continue
            if self._starts_with("<?"):
                self.pos += 2
                var ts = self.pos
                while self.pos < len(self.src) and _is_name_byte(self.src[self.pos]):
                    self.pos += 1
                if self.pos == ts or not (self._starts_with("?>") or _is_space(self._peek())):
                    raise make_error(self.src, start, "", "bad processing instruction target")
                self._skip_past("?>", start)
                continue
            if self._starts_with("<!DOCTYPE"):
                self._skip_past(">", start)
                continue
            if self._starts_with("<!"):
                raise make_error(self.src, start, "", "unknown markup declaration")
            if self._starts_with("</"):
                self.pos += 2
                var ns = self.pos
                self._skip_name()
                var ne = self.pos
                self._skip_space()
                if self._peek() != GT:
                    raise make_error(self.src, start, "", "malformed end tag </" + self._str(ns, ne))
                self.pos += 1
                return Token(TokenKind.END, ns, ne, False, False, start)
            # start tag
            self.pos += 1
            var ns = self.pos
            self._skip_name()
            var ne = self.pos
            if ne == ns:
                raise make_error(self.src, start, "", "empty tag name")
            if not _is_name_start(self.src[ns]):
                raise make_error(self.src, start, "", "tag name cannot start with its first byte: <" + self._str(ns, ne) + ">")
            self.attrs.clear()
            var self_closing = False
            while True:
                self._skip_space()
                var c = self._peek()
                if c == GT:
                    self.pos += 1
                    break
                if c == SLASH:
                    self.pos += 1
                    self._skip_space()
                    if self._peek() != GT:
                        raise make_error(self.src, start, "", "expected '>' after '/' in <" + self._str(ns, ne) + ">")
                    self.pos += 1
                    self_closing = True
                    break
                if c == 0:
                    raise make_error(self.src, start, "", "unterminated start tag <" + self._str(ns, ne) + ">")
                var an_s = self.pos
                self._skip_name()
                var an_e = self.pos
                if an_e == an_s or not _is_name_start(self.src[an_s]):
                    raise make_error(self.src, start, "", "bad attribute in <" + self._str(ns, ne) + ">")
                for a in self.attrs:
                    if bytes_eq(self.src, a.name_s, a.name_e, an_s, an_e):
                        raise make_error(
                            self.src, start, "",
                            "duplicate attribute '" + self._str(an_s, an_e) + "' in <" + self._str(ns, ne) + ">",
                        )
                self._skip_space()
                if self._peek() != EQ:
                    raise make_error(self.src, start, "", "attribute without '=' in <" + self._str(ns, ne) + ">")
                self.pos += 1
                self._skip_space()
                var q = self._peek()
                if q != DQ and q != SQ:
                    raise make_error(
                        self.src, start, "",
                        "expected quote for attribute '" + self._str(an_s, an_e) + "' in <" + self._str(ns, ne) + ">",
                    )
                self.pos += 1
                var vs = self.pos
                while self.pos < len(self.src) and self.src[self.pos] != q:
                    if self.src[self.pos] == LT:
                        raise make_error(self.src, start, "", "'<' in attribute value in <" + self._str(ns, ne) + ">")
                    self.pos += 1
                if self.pos >= len(self.src):
                    raise make_error(self.src, start, "", "unterminated attribute value in <" + self._str(ns, ne) + ">")
                self.attrs.append(Attr(an_s, an_e, vs, self.pos))
                self.pos += 1
                var nb = self._peek()
                if not (_is_space(nb) or nb == GT or nb == SLASH or nb == 0):
                    raise make_error(self.src, start, "", "missing space between attributes in <" + self._str(ns, ne) + ">")
            return Token(TokenKind.START, ns, ne, self_closing, False, start)
