# xmojo errors and fixes

| message contains | cause | fix |
|---|---|---|
| `missing field: x (MissingField)` | a required field has no attribute, child or text named `x` | `Optional[T]`, `Defaulted[T, v]`, a `List`, or fix the field name (local name, case-sensitive); `Rename[...]` if the wire name differs |
| `unknown attribute @x` / `unknown element <x>` (UnknownField) | the struct conforms to `DenyUnknownFields` | add the field, or drop `DenyUnknownFields` |
| `unknown entity &x;` | an HTML entity in XML | pass `html_entities()` (or your own map) as `entities` |
| `bare '&'` | an unescaped `&` in text or an attribute | the input is not XML; escape it as `&amp;` upstream |
| `unsupported encoding` | the XML declaration names a non-UTF-8 encoding | transcode to UTF-8 before parsing |
| `undeclared namespace prefix 'p'` | `p:` used without an `xmlns:p` in scope | fix the input; for `Records` the ancestors' declarations are copied in already |
| `mismatched end tag`, `unclosed element`, `content after the root element` | not well-formed XML | fix the input; xmojo does not recover |
| `not a number` / `not a boolean` (TypeMismatch) | text does not fit `Int`/`Float64`/`Bool` (`true/false/1/0`) | use `String` or `Optional`, or clean the input |
| `enum 'f' has no arm 'X'` | the text is not one of the `ArmName`s | add the arm or decode as `String` |
| `input over 2 GiB is not supported` | `parse`/`from_xml` on a huge document | `Records` over it |
| a build that never finishes | Mojo 1.1 front-end hang on some loop shapes | move the loop body into a function; build with a timeout |
| code changes that do not take effect | a stale `xmojo.mojoc` next to your main file shadows `-I src` | delete it or move the probe |
