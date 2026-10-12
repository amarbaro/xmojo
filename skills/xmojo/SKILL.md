---
name: xmojo
description: Read and write XML in Mojo with xmojo. Use when Mojo code has to parse XML (feeds, Atom, RSS, PubMed/NCBI E-utilities, configs, SOAP-like payloads) into structs, write structs as XML, stream large XML files record by record, or walk an XML tree; also when fixing xmojo errors (MissingField, UnknownField, XmlError) or contributing to the xmojo repository. Covers install, the struct mapping, emberserde field modifiers, streaming, the DOM, and the traps agents hit.
---

<!-- A correction layer for an agent's context: every line costs context. Keep it terse, keep
every complete Mojo program runnable: tools/check_snippets.py compiles and runs each block that
has a `def main`, in the gate. -->

# xmojo

XML for Mojo 1.1: `from_xml[T]` (XML into a struct), `to_xml` (struct into XML), `Records`
(stream one element at a time), `parse` (flat DOM). Decoding goes through emberserde, so the
same struct also works with EmberJson. Mojo syntax itself (no `fn`, `comptime`, `def main()
raises`) comes from Modular's `mojo-syntax` skill.

## Install

pixi, with the modular-community channel for emberserde:

```toml
[workspace]
channels = ["https://conda.modular.com/max", "https://repo.prefix.dev/modular-community", "conda-forge"]
platforms = ["linux-64"]

[dependencies]
mojo = "==1.1.0"
emberserde = "==0.1.0"
```

Then either the conda package built from xmojo's `recipe.yaml`, or a checkout of the repository
with `mojo run -I <xmojo>/src your_file.mojo`. Import from the package root:
`from xmojo import from_xml, to_xml, Records, parse, html_entities, XmlError`.

## Decode and encode

```mojo
from xmojo import from_xml, to_xml


@fieldwise_init
struct Link(Copyable, Defaultable, Movable):
    var href: String                  # attribute href
    var rel: Optional[String]         # attribute rel, None when absent

    def __init__(out self):
        self.href = ""
        self.rel = None


@fieldwise_init
struct Entry(Copyable, Defaultable, Movable):
    var id: Int                       # attribute id, or a child <id>text</id>
    var title: String                 # child <title>
    var link: List[Link]              # every child <link>, [] when there is none
    var text: String                  # the element's own text ("" when it has none)

    def __init__(out self):
        self.id = 0
        self.title = ""
        self.link = List[Link]()
        self.text = ""


def main() raises:
    var e = from_xml[Entry]('<entry id="7"><title>T</title><link href="a" rel="alternate"/>body</entry>')
    print(e.id, e.title, len(e.link), e.link[0].rel.value(), e.text)   # 7 T 1 alternate body
    print(to_xml(e, "entry"))   # scalars go out as attributes, so title does too:
    # <entry id="7" title="T"><link href="a" rel="alternate"/>body</entry>
```

## Struct rules

| need | write |
|---|---|
| a decodable struct | `Copyable, Movable` plus `Defaultable` with an explicit `def __init__(out self)` (or only number/`Bool`/nested-struct fields, then `Defaultable` is optional) |
| attribute or child element | a field of that local name; attribute wins over child, child over text |
| element text | a field named `text` |
| all attributes as a map | `var attrs: Dict[String, String]` |
| repeated children | `List[T]` (absent: `[]`) |
| optional value | `Optional[T]` (absent: `None`) |
| enum | `Variant` of fieldless structs that conform to `ArmName` (unit arms only) |
| another wire name | `Rename[String, "userName"]`, struct-wide `RenameAll` (emberserde) |
| default when absent | `Defaulted[Int, 3]`; never read or written: `Skip[T]` |
| accept old names | `Field[String, extra_names=List[String](["mail"])]` |
| reject unknown attributes/children | conform the struct to `DenyUnknownFields` |

Fields match by local name: `arxiv:doi` and `doi` both bind `var doi`. Unknown attributes and
children are skipped (unless `DenyUnknownFields`). A required field with no source raises
`MissingField` ("missing field: name"). Map keys must be `String` (anything else fails to
compile).

## Output (to_xml)

Scalars become attributes, the field `text` the element text, structs and list items child
elements named after the field, `None` nothing, an `attrs` map attributes. Values are escaped so
`from_xml[T](to_xml(v, "root"))` gives `v` back. The root value must be a struct; there is no
namespace output and no pretty-printing.

## Big files and trees

```mojo
from xmojo import from_xml, Records, parse


@fieldwise_init
struct Item(Copyable, Defaultable, Movable):
    var n: Int

    def __init__(out self):
        self.n = 0


def main() raises:
    var text = String("<feed xmlns:x='urn:x'><item n='1'/><item n='2'><x:note/></item></feed>")
    var it = Records(text, "item")   # `text` must outlive `it`
    var total = 0
    while True:
        var rec = it.next()          # Optional[String]: one standalone <item>, ancestors' xmlns copied in
        if not rec:
            break
        total += from_xml[Item](rec.value()).n
    print(total)                     # 3

    var d = parse(text)              # elements numbered in document order, root 0
    for c in d.children(d.root()):
        print(d.name(c), d.attr(c, "n").value(), len(d.children(c)))
```

`Records` bounds the tree, not the input: the text stays in memory. Each record is copied and
parsed on its own, which costs more than one whole-document `from_xml` on tiny records. The
`Doc` API (`name`, `local_name`, `prefix`, `ns`, `text`, `attr`, `attr_ns`, `children_named`, ...)
is listed in `references/api.md`.

## Traps

| WRONG | RIGHT |
|---|---|
| expecting `&nbsp;` to decode | `from_xml[T](text, html_entities())`; build the map once, reuse it |
| ISO-8859-1 or UTF-16 input | transcode to UTF-8 first; other declared encodings raise |
| matching a field on `prefix:name` | fields bind by local name; check the namespace with `Doc.ns(i)` / `attr_ns` |
| whitespace-only text kept | dropped, unless the element is under `xml:space="preserve"` |
| `parse` on input over 2 GiB | raises; use `Records` (each record up to 2 GiB) |
| a probe file next to an old `xmojo.mojoc` | the main file's directory is searched before `-I`: a stale `.mojoc` there silently replaces `src/`. Keep probes in a directory without packages |
| `Dict[Int, V]` field | keys must be `String` |
| enum arm with a payload | unit arms only; the arm name is the whole value |

Errors and their fixes: `references/errors.md`.

## Working on xmojo itself

`pixi run gate` (unit tests, tool builds, `tools/oracle.py` against CPython's expat on 2 seeds,
the `--negative` control, every runnable snippet in README and this skill). A parsing change adds
a generator case or fixture to the oracle and a regression test. A performance claim shows
`tools/ab.sh` medians from binaries built from the same benchmark source. See CONTRIBUTING.md.
