# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Streaming over repeated elements without a whole-document DOM: memory is the input plus one
# record, not the document's tree.
from .tokenizer import Tokenizer, TokenKind, Attr, check_decl, bytes_eq
from .error import XmlError


struct Records[origin: ImmOrigin](Movable):
    """Yields, one per `next()` call, each element whose local name is `local` (its outermost
    occurrences: matches nested inside a record are part of that record). Every record comes back
    as standalone XML for `parse`/`from_xml`, with the namespace declarations of its ancestors
    copied into its start tag:

        var it = Records(text, "PubmedArticle")
        while True:
            var rec = it.next()
            if not rec:
                break
            var article = from_xml[Article](rec.value())
    """

    var tok: Tokenizer[Self.origin]
    var local: String
    var decls: List[Attr]       # xmlns* attributes of the open ancestors, outermost first
    var counts: List[Int]       # how many of `decls` each open ancestor added
    var checked: Bool

    def __init__(out self, text: StringSlice[Self.origin], local: String):
        self.tok = Tokenizer(text)
        self.local = local
        self.decls = List[Attr]()
        self.counts = List[Int]()
        self.checked = False

    def next(mut self) raises XmlError -> Optional[String]:
        ref src = self.tok.src
        if not self.checked:
            self.checked = True
            check_decl(src)
        while True:
            var t = self.tok.next()
            if t.kind == TokenKind.EOF:
                return None
            if t.kind == TokenKind.END:
                if len(self.counts) > 0:
                    for _ in range(self.counts.pop()):
                        _ = self.decls.pop()
                continue
            if t.kind != TokenKind.START:
                continue
            var colon = t.s - 1
            for k in range(t.s, t.e):
                if src[k] == 58:
                    colon = k
            if String(unsafe_from_utf8=src[colon + 1 : t.e]) == self.local:
                return self._record(t.e, t.start, t.self_closing)
            if not t.self_closing:
                var n = 0
                for a in self.tok.attrs:
                    if a.name_e - a.name_s >= 5 and String(unsafe_from_utf8=src[a.name_s : a.name_s + 5]) == "xmlns":
                        self.decls.append(a)
                        n += 1
                self.counts.append(n)

    def _record(mut self, ne: Int, start: Int, self_closing: Bool) raises XmlError -> String:
        ref src = self.tok.src
        var own = self.tok.attrs.copy()
        var depth = 0 if self_closing else 1
        while depth > 0:
            var t = self.tok.next()
            if t.kind == TokenKind.EOF:
                break   # unclosed: parse reports it
            if t.kind == TokenKind.START and not t.self_closing:
                depth += 1
            elif t.kind == TokenKind.END:
                depth -= 1
        var out = String(unsafe_from_utf8=src[start:ne])
        for k in range(len(self.decls) - 1, -1, -1):   # innermost declaration of a name wins
            ref d = self.decls[k]
            var seen = False
            for a in own:
                seen = seen or bytes_eq(src, a.name_s, a.name_e, d.name_s, d.name_e)
            if not seen:
                out += " " + String(unsafe_from_utf8=src[d.name_s : d.val_e + 1])
                own.append(d)
        return out + String(unsafe_from_utf8=src[ne : self.tok.pos])
