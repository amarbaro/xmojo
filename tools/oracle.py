#!/usr/bin/env python3
# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
"""Differential oracle: xmojo's DOM (tools/xmldump.mojo) vs expat, on seeded random documents,
mutated (mostly malformed) copies, and tests/fixtures. expat is the XML parser of record;
xmojo's documented whitespace rule (whitespace-only text runs between markup are dropped,
CDATA never) is applied on top of expat's events. Usage: oracle.py [N] [SEED] [--negative]
--negative corrupts the reference (every text line gets a trailing "!") and must FAIL to match:
it proves the comparison can go red."""
import pathlib, random, re, subprocess, sys, xml.parsers.expat

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / ".work/oracle"
WSB = set(b" \t\n\r")
XML_NS = "http://www.w3.org/XML/1998/namespace"


def esc(s):
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")


def ref_dump(data):
    """Same format as xmldump, from expat events."""
    # xmojo policy: only UTF-8 / US-ASCII may be declared (Python's codec lookup is looser).
    m = re.match(rb"(?:\xef\xbb\xbf)?<\?xml\s[^>]*?encoding\s*=\s*['\"]([^'\"]*)['\"]", data)
    if m and m.group(1).lower() not in (b"utf-8", b"us-ascii"):
        return ["ERROR"]
    p = xml.parsers.expat.ParserCreate(namespace_separator=" ")
    p.buffer_text = False
    nodes, stack, run, cdata, run_at = [], [], [], [None], [0]

    def name(n):
        return "{%s}%s" % tuple(n.split(" ")) if " " in n else n

    def flush():
        # xmojo's rule looks at the raw run, so "&#13;" is kept though it decodes to whitespace.
        if run and stack and (stack[-1][5] or not set(data[run_at[0] : p.CurrentByteIndex]) <= WSB):
            stack[-1][3].append("".join(run))
        run.clear()

    def start(n, attrs):
        flush()
        space = attrs.get(XML_NS + " space")
        keep = space == "preserve" or (space != "default" and bool(stack) and stack[-1][5])
        node = [len(stack), name(n), sorted((name(k), v) for k, v in attrs.items()), [], [], keep]
        (stack[-1][4] if stack else nodes).append(node)
        stack.append(node)

    def end(n):
        flush()
        stack.pop()

    def chars(s):
        if cdata[0] is not None:
            cdata[0].append(s)
            return
        if not run:
            run_at[0] = p.CurrentByteIndex
        run.append(s)

    def cdata_start():
        flush()
        cdata[0] = []

    def cdata_end():
        if stack:
            stack[-1][3].append("".join(cdata[0]))
        cdata[0] = None

    p.StartElementHandler, p.EndElementHandler, p.CharacterDataHandler = start, end, chars
    p.StartCdataSectionHandler, p.EndCdataSectionHandler = cdata_start, cdata_end
    p.CommentHandler = p.ProcessingInstructionHandler = lambda *a: flush()
    try:
        p.Parse(data, True)
    except (xml.parsers.expat.ExpatError, LookupError):   # LookupError: unknown declared encoding
        return ["ERROR"]
    out, todo = [], nodes[::-1]
    while todo:
        n = todo.pop()
        out.append("E %d %s" % (n[0], n[1]))
        out.extend("A %s=%s" % (k, esc(v)) for k, v in n[2])
        if "".join(n[3]):
            out.append("T " + esc("".join(n[3])))
        todo.extend(n[4][::-1])
    return out


NAMES = ["a", "b", "item", "x-y", "n.1", "_u", "é"]
TEXT = ["hi", " ", "\n  ", "a&amp;b", "&lt;x&gt;", "&#65;&#x42;", "<![CDATA[x<y&]]>", "<![CDATA[]]>",
        "<!-- c -->", "<?pi x?>", "<?pi?>", "ü€", "  two  words ", "\r\n", "\r", "q&quot;&apos;", "a & b",
        "&#1;", "&#xD800;", "&#13;"]
VALS = ["v", "a&amp;b", "x y", "'", "&quot;", "tab\there", "nl\nx", "cr\r\nx", "&#x263A;", "&#10;", ""]


def gen(r, depth, ns):
    tag = (r.choice(["p:", ""]) if ns else "") + r.choice(NAMES)
    attrs = [(r.choice(["p:", "xml:", ""]) if ns else "") + a for a in r.sample(NAMES, r.randint(0, 3))]
    attrs = list(dict.fromkeys(attrs))
    if r.random() < 0.15:
        attrs.append("xml:space")
    q = r.choice("'\"")
    head = "".join(" %s=%s%s%s" % (a, q, r.choice(["preserve", "default"]) if a == "xml:space" else r.choice(VALS).replace(q, "&#%d;" % ord(q)), q) for a in attrs)
    if depth == 0:
        head += ' xmlns="urn:d" xmlns:p="urn:p"' if ns else ""
    if depth > 3 or r.random() < 0.2:
        return "<%s%s/>" % (tag, head)
    body = "".join(r.choice(TEXT) if r.random() < 0.5 else gen(r, depth + 1, ns) for _ in range(r.randint(0, 4)))
    return "<%s%s>%s</%s>" % (tag, head, body, tag)


def mutate(r, s):
    i = r.randrange(len(s))
    return r.choice([
        lambda: s[:i] + s[i + 1:],
        lambda: s[:i] + "<" + s[i:],
        lambda: s[:i] + "&bogus;" + s[i:],
        lambda: s.replace(">", " a='1' a='2'>", 1),
        lambda: s[: s.rfind("</")] if "</" in s else s + "</z>",
    ])()


def main():
    negative = "--negative" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--negative"]
    n = int(args[0]) if args else 500
    r = random.Random(int(args[1]) if len(args) > 1 else 1)
    gen_dir = WORK / "gen"
    gen_dir.mkdir(parents=True, exist_ok=True)
    for old in gen_dir.glob("*.xml"):
        old.unlink()
    files = sorted(p for p in (ROOT / "tests/fixtures").rglob("*") if p.suffix in (".xml", ".atom"))
    for k in range(n):
        decl = r.choice(["", "", "<?xml version='1.0'?>\n", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                         "<?xml version='1.1' encoding='utf-8' standalone='yes'?>"])
        doc = r.choice(["", "", "\ufeff"]) + decl + gen(r, 0, r.random() < 0.4)
        if k % 5 == 4:
            doc = mutate(r, doc)
        path = gen_dir / ("%04d.xml" % k)
        path.write_bytes(doc.encode())
        files.append(path)
    res = subprocess.run([str(ROOT / ".work/xmldump")] + [str(f) for f in files], capture_output=True)
    if res.returncode != 0:
        print("FAIL xmldump: exit %d\n%s" % (res.returncode, res.stderr.decode()[-2000:]))
        sys.exit(1)
    got, cur = {}, None
    for line in res.stdout.decode().split("\n"):
        if line.startswith("== "):
            cur = got[line[3:]] = []
        elif line:
            cur.append(line)
    bad, report = [], []
    for f in files:
        mine = got.get(str(f), ["<missing>"])
        # xmldump prints attributes in document order; expat's are sorted.
        mine = [l for blk in _blocks(mine) for l in blk]
        ref = ref_dump(f.read_bytes())
        if negative:
            ref = [l + "!" if l.startswith("T ") else l for l in ref]
        if mine != ref:
            bad.append(f.name)
            k = next((j for j, (a, b) in enumerate(zip(mine, ref)) if a != b), min(len(mine), len(ref)))
            report.append("== %s\n  line %d\n  xmojo: %s\n  expat: %s" % (
                f, k, mine[k] if k < len(mine) else "<end>", ref[k] if k < len(ref) else "<end>"))
    (WORK / "diff.txt").write_text("\n".join(report) + "\n")
    if negative:
        if not bad:
            print("FAIL negative control: a corrupted reference still matched %d/%d" % (len(files), len(files)))
            sys.exit(1)
        print("negative control OK: %d/%d differ from a corrupted reference" % (len(bad), len(files)))
        return
    if bad:
        print("FAIL %d/%d %s (details: %s)" % (len(bad), len(files), " ".join(bad[:12]), WORK / "diff.txt"))
        sys.exit(1)
    print("OK %d/%d" % (len(files), len(files)))


def _blocks(lines):
    """Sort each run of consecutive A lines, leaving everything else in place."""
    out, attrs = [], []
    for l in lines + [""]:
        if l.startswith("A "):
            attrs.append(l)
            continue
        if attrs:
            out.append(sorted(attrs, key=lambda a: a[2:].split("=", 1)[0]))
            attrs = []
        if l:
            out.append([l])
    return out


if __name__ == "__main__":
    main()
