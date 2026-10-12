# xmojo API

All names import from the package root: `from xmojo import ...`.

## Functions

| signature | notes |
|---|---|
| `from_xml[T](s: StringSlice, entities: Dict[String, String] = {}) raises -> T` | parse errors arrive as `DeserializationError` with the `XmlError` text |
| `to_xml[T](v: T, root: StringSlice) raises SerializationError -> String` | `root` names the outer element |
| `parse(s: StringSlice, entities: Dict[String, String] = {}) raises XmlError -> Doc` | |
| `html_entities() raises -> Dict[String, String]` | 2120 WHATWG names; builds a new map per call |
| `Records(text: StringSlice, local: String)`; `next(mut self) raises XmlError -> Optional[String]` | `None` at the end; borrows `text` |

## Doc

Elements are numbered in document order; the root is `0` (`root()`); `len(doc)` is the count.

| method | returns |
|---|---|
| `name(i)` | qualified name as written (`arxiv:doi`) |
| `local_name(i)`, `prefix(i)` | `doi`, `arxiv` (`""` without a prefix) |
| `ns(i)` | resolved namespace URI, `""` for none |
| `text(i)`, `has_text(i)` | text and CDATA children concatenated |
| `attr(i, name)` | `Optional[String]`, by qualified name |
| `attr_ns(i, ns, local)` | `Optional[String]`; `ns=None` matches any namespace; unprefixed attributes have namespace `""` |
| `attr_names(i)` | qualified names, `xmlns` declarations included |
| `parent(i)` | `-1` for the root |
| `children(i)` | `List[Int]` |
| `children_named(i, local)`, `children_ns(i, ns, local)`, `child_local_names(i)` | filtered children, distinct local names |

Accessors return owned `String`s. Layout (for memory estimates): a 36-byte record per element,
16 bytes per attribute, names and namespace URIs interned per document, decoded text in one byte
pool.

## XmlError

Fields `message`, `line` and `col` (1-based, bytes) and `tag` (nearest open element, `""` at top
level). `String(e)` is `xmojo: <message> at <line>:<col>` plus ` in <tag>` when an element is open.

## XML handling

XML 1.0 well-formedness and Namespaces in XML: `xmlns`/`xmlns:p` with lexical scope, prefixed
attributes resolved, `xml:` predeclared. CR LF and CR become LF; literal tab/LF/CR in attribute
values become spaces; character references are kept as written. XML's five entities and numeric
references always; others only from the `entities` map. A UTF-8 BOM is skipped; a declared
encoding other than UTF-8/US-ASCII raises. DTDs are skipped, not processed.
