# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Canonical dump of xmojo's DOM, one section per input file, for tools/oracle.py:
#   == <path>            then per element in document order:
#   E <depth> <{ns}local>
#   A <name>=<value>     attributes (xmlns* excluded), one per line, unsorted
#   T <text>             element text, if any
# or "ERROR" when parse raises. Backslash, newline, CR and tab are escaped.
from std.sys import argv
from xmojo import Doc, parse


def _esc(s: String) -> String:
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")


def _dump(d: Doc, mut out: String):
    var todo: List[Int] = [d.root()]
    var depths: List[Int] = [0]
    while todo:
        var i = todo.pop()
        var depth = depths.pop()
        var ns = d.ns(i)
        out += "E " + String(depth) + " " + (d.local_name(i) if ns == "" else "{" + ns + "}" + d.local_name(i)) + "\n"
        for k in range(Int(d.nodes[i].attr0), Int(d.nodes[i].attr0 + d.nodes[i].nattr)):
            var a = d.names[Int(d.attrs[k].name)].copy()
            if a != "xmlns" and not a.startswith("xmlns:"):
                var uri = d.uris[Int(d.attrs[k].ns)].copy()
                var local = d.names[Int(d.local_of[Int(d.attrs[k].name)])].copy()
                out += "A " + (local if uri == "" else "{" + uri + "}" + local) + "=" + _esc(d.attr(i, a).value()) + "\n"
        if d.has_text(i):
            out += "T " + _esc(d.text(i)) + "\n"
        var kids = d.children(i)
        for k in range(len(kids) - 1, -1, -1):
            todo.append(kids[k])
            depths.append(depth + 1)


def main() raises:
    var args = argv()
    var out = String()
    for k in range(1, len(args)):
        var path = String(args[k])
        out += "== " + path + "\n"
        try:
            var d = parse(open(path, "r").read())
            _dump(d, out)
        except:
            out += "ERROR\n"
    print(out, end="")
