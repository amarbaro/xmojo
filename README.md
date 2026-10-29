# xmojo

XML for Mojo: parse into your own structs, write them back, stream big documents record by
record. Every gate run checks the parser against CPython's expat on 4,030 generated, mutated and
real documents with zero disagreements, and it parses 1.5 to 1.7 times faster than CPython's
C-backed ElementTree on the same input.

Decoding and encoding walk your struct's fields with Mojo's standard `reflection` module: no
dependency beyond the Mojo standard library.

| | |
|---|---|
| read | `from_xml[Entry](text)`: attributes, child elements and text bound to fields by name |
| write | `to_xml(entry, "entry")`: the mirror of `from_xml`, round-trips |
| stream | `Records(text, "PubmedArticle")`: one record at a time, the tree bounded by one record |
| tree | `parse(text) -> Doc`: a flat arena DOM, about 100 bytes per element |

Not supported: DTDs (an internal subset is skipped, so its entities are unknown), encodings other
than UTF-8 and US-ASCII, XPath or any query language, enum arms with payloads, tuples. Streaming
still holds the whole input in memory; only the tree is bounded.

## Performance

`tools/bench.sh` (`pixi run bench`): best of 5, Mojo 1.2.0, one core of a Ryzen 7 7800X3D.

| case | xmojo | peak RSS | CPython 3.13 ElementTree |
|---|---|---|---|
| parse, 80k sibling elements (1.1 MB) | 18.0 ms | 22.2 MB | 26.8 ms |
| parse, 80k nested elements | 11.4 ms | 23.9 MB | 19.1 ms |
| parse, arXiv Atom fixture x2000 | 30.8 ms | | 50.9 ms |
| `from_xml`, 80k items | 28.0 ms | 24.7 MB | |
| `Records` + `from_xml` per item, 80k | 84.1 ms | 15.0 MB | |
| `to_xml`, 80k items (1.43 MB out) | 5.3 ms | 20.0 MB | |

ElementTree also builds Python objects, so its column places xmojo rather than ranks it.
Streaming trades time for memory: each record is copied and parsed into its own `Doc`, which
makes it 3 times slower than whole-document `from_xml` on the 14-byte records above. Records
of real size amortize that cost.

## Setup

[pixi](https://pixi.sh) installs Mojo 1.2.0 and the Python that runs the oracle, both pinned in
`pixi.lock`:

```
pixi install
pixi run test      # unit tests
pixi run gate      # unit tests, tool builds, expat differential, negative control
```

From another project: build with `-I src`, or install the conda package (see Packaging).

## Usage

```mojo
from xmojo import from_xml, to_xml, Records, parse


@fieldwise_init
struct Link(Copyable, Defaultable, Movable):
    var href: String                 # <- attribute href
    var title: Optional[String]      # <- attribute title, None if absent

    def __init__(out self):
        self.href = ""
        self.title = None


@fieldwise_init
struct Entry(Copyable, Defaultable, Movable):
    var title: String                # <- <title>text</title>
    var link: List[Link]             # <- every <link .../> child

    def __init__(out self):
        self.title = ""
        self.link = List[Link]()


def main() raises:
    var text = String('<entry><title>Hi</title><link href="a"/><link href="b" title="B"/></entry>')
    var e = from_xml[Entry](text)              # e.link[1].title.value() == "B"
    var back = from_xml[Entry](to_xml(e, "entry"))  # round trip: back.link[1].title == "B"

    var it = Records(text, "link")             # one <link> at a time, as standalone XML
    while True:
        var rec = it.next()
        if not rec:
            break
        print(from_xml[Link](rec.value()).href)

    var d = parse(text)                        # the tree: element 0 is the root
    print(d.name(0), len(d.children(0)), d.attr(3, "title").value())   # entry 3 B
```

`tests/test_readme.mojo` runs this example with its comments as assertions in every gate.

## For agents

`skills/xmojo/SKILL.md` is an agent skill (install, mapping, streaming, traps, error fixes), in
the layout of Modular's skills repository; Claude Code: `/plugin marketplace add amarbaro/xmojo`.
`AGENTS.md` points other agents at it. Its runnable examples are compiled and run by the gate.

## Mapping

| field type | from (`from_xml`) and to (`to_xml`) |
|---|---|
| `String`, `Int`, `Float64`, `Bool` | attribute of that local name, else a child element of that name (its text), else the element's text for a field named `text` |
| `Optional[T]` | `None` when absent (omitted on output), else `T`'s rule |
| `List[T]` | every child element with that local name, in order |
| `Dict[String, V]` | the element's attributes for a field named `attrs`, otherwise its children keyed by local name |
| unit enum (`Variant` of fieldless `ArmName` structs) | attribute or element text matched against the arm names |
| nested struct | the first child element with that local name |

Field and struct modifiers, imported from `xmojo`: `Rename`, `RenameAll`, `Skip`, `Defaulted`
(the default when the field is absent), `Field[..., extra_names=...]` aliases and
`DenyUnknownFields` (an unknown attribute or child raises "unknown attribute" or "unknown
element"); see
`tests/test_xmojo_fields.mojo`. Fields match by local name, ignoring prefixes (`arxiv:doi` binds a field `doi`). Unknown elements
and attributes are skipped. A required field with no source raises "missing field: <name>"; a field named
`text` on an element without text is `""`. On output, scalars become attributes, a field named
`text` the element's text, structs and list items child elements, and values are escaped so that
`from_xml[T](to_xml(v, "r"))` gives `v` back.

## DOM

`parse(text, entities=...) -> Doc`. Elements are numbered in document order, root `0`, and read
through the `Doc`: `name(i)` (qualified), `local_name(i)`, `prefix(i)`, `ns(i)`, `text(i)` (text
and CDATA concatenated), `has_text(i)`, `attr(i, name)`, `attr_ns(i, ns, local)`, `attr_names(i)`,
`parent(i)` (`-1` for the root), `children(i)`, `children_named(i, local)`,
`children_ns(i, ns, local)`, `child_local_names(i)`; `len(doc)` is the element count.

One 36-byte `Node` record per element in a flat list (ids and offsets); element and attribute
names and namespace URIs interned once per document; decoded text and attribute values in one
byte pool. The tokenizer reports byte ranges of the input and reuses one attribute buffer, so it
allocates nothing per tag. Nesting depth is bounded by memory, not the call stack.

## XML handling

- Namespaces: `xmlns` and `xmlns:p` resolve with lexical scoping; prefixed attributes resolve
  too; `xml:` is predeclared; an undeclared prefix raises.
- Text: CR LF and CR become LF; literal tab, LF and CR in attribute values become spaces;
  character references are kept as written. Whitespace-only text between markup is dropped
  unless `xml:space="preserve"` is in scope.
- Entities: XML's five plus numeric references. HTML's named references are opt-in:
  `parse(text, html_entities())` (all 2120 WHATWG names) or any `Dict[String, String]` of your
  own. Without a map, `&nbsp;` raises.
- Encoding: UTF-8 input. A UTF-8 byte order mark is skipped; a declared encoding other than UTF-8
  or US-ASCII raises (transcode first).
- Errors: malformed input raises `XmlError` with a message, 1-based line and column (bytes) and
  the nearest open element; `from_xml` reports it as a `DeserializationError` with the same text.
  The parser does not recover.

## Verification

`tools/oracle.py` generates seeded random documents inside xmojo's scope (names, prefixes and
declarations, attributes, entities and character references, CDATA, comments, processing
instructions, mixed content, `xml:space`, encodings, byte order marks), mutates every fifth one
(most become malformed), adds every file in `tests/fixtures/`, and compares `tools/xmldump.mojo`
(xmojo's tree, one process for all files) with expat's events element by element, including
whether a document is rejected. xmojo's documented whitespace and encoding rules are applied to
the expat side.

```
pixi run oracle 2000 1             # 2015 documents, seed 1
pixi run oracle 200 1 --negative   # corrupted reference: must report mismatches
pixi run gate                      # the above for seeds 1 and 7, unit tests, tool builds, doc snippets
```

The negative control feeds the comparison a corrupted reference and must fail, so a green gate
means the comparison ran. Its first run found eleven classes of malformed input the parser used
to accept, from a bare `&` to a second root element; each is rejected now and has a regression
case in `tests/test_xmojo_errors.mojo`.

## Packaging

`recipe.yaml` (modular-community shape) builds a precompiled `.conda` and runs the unit tests
against the installed `xmojo.mojoc`: `pixi run package` (needs `rattler-build`), output in
`.work/conda/`. Not yet on modular-community.

## License

Apache-2.0, copyright amarbaro.org. See LICENSE and NOTICE, which also covers the third-party
data: the WHATWG entity list and the arXiv test fixture.
