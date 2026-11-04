# Design

xmojo parses XML 1.5 to 1.7 times faster than CPython's C-backed ElementTree on one core
(README, Performance) by never building an object per element: the document is one flat array of
36-byte records plus two pools. The cost of that choice is streaming: `Records` is 3 times slower
than whole-document `from_xml` on 14-byte records, because each record is copied and parsed into
its own `Doc`.

## The tokenizer allocates nothing per tag

`tokenizer.mojo` reports byte ranges into the input and reuses one attribute buffer for every
tag. Text and attribute values are decoded (line endings, references, entities) only when they
are stored, straight into the document's byte pool.

## A document is a flat array, not a tree of objects

`dom.mojo`: one `Node` record per element in document order (root `0`), holding ids and offsets;
names and namespace URIs interned once per document; decoded text and values in one byte pool.
Every DOM call (`name(i)`, `children(i)`, `attr(i, name)`) is an index lookup. Nesting depth is
bounded by memory, not the call stack, so `tests/fixtures/bad/depth_10000.xml` is a parse
result, not a crash.

## Structs map by reflection, with no code generation

`decode.mojo` and `encode.mojo` walk a struct's fields with the standard `reflection` module: a
`String` or scalar field binds to an attribute or a child's text by name, `Optional[T]` is
absent-or-present, `List[T]` collects repeated children. There is no macro, schema or generated
code, so the mapping rules are the README "Mapping" section and nothing else.

## Malformed input raises, it is never repaired

The parser does not recover. Every error is an `XmlError` with a message, a 1-based line and byte
column, and the nearest open element. Unknown entities raise unless the caller passes a map
(`html_entities()` or a `Dict`), and a declared encoding other than UTF-8 or US-ASCII raises.
A parser that guesses would disagree with expat, and expat is the oracle.

## Not supported

Encodings other than UTF-8 (transcode first), DTDs (a DOCTYPE is skipped, so entities its internal subset declares are unknown),
validation, XPath, and error recovery.

## How to prove it wrong

`tools/oracle.py` compares xmojo's tree with expat's events element by element on seeded generated
documents, a mutated fifth of them, and every file in `tests/fixtures/`, including whether a
document is rejected. Its negative control feeds a corrupted reference and must fail.
`pixi run gate` runs it for two seeds; a document where xmojo and expat disagree is a bug.
