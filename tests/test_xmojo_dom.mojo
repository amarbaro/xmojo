# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
from std.testing import assert_equal, assert_true, TestSuite
from xmojo import parse, html_entities, Doc

from std.os import getenv


def _fixtures() -> String:
    """Fixture dir: tests/fixtures from the repository root, or $XMOJO_FIXTURES."""
    var v = getenv("XMOJO_FIXTURES")
    return v if v != "" else String("tests/fixtures")


def test_len_is_element_count() raises:
    # review C, xmojo P1: README says len(doc) is the element count; it did not compile
    assert_equal(len(parse("<a><b/><c><d/></c></a>")), 4)


def test_mixed_content_is_linear() raises:
    # review C, xmojo P2: text resuming after a child copied the whole text each time (O(n^2) pool)
    var s = String("<p>")
    for _ in range(20000):
        s += 't<b c="1"/>u<i>v</i>'
    s += "</p>"
    var d = parse(s)
    assert_equal(d.text(0).byte_length(), 40000)
    assert_equal(d.attr(1, "c").value(), "1")
    assert_true(len(d.pool) < 4 * s.byte_length(), "pool must stay linear in the input")


def test_nested_namespace_declarations_are_linear() raises:
    # review C, xmojo P2: every declaring element copied its parent's whole scope (O(depth^2) memory)
    var n = 6000
    var s = String()
    for i in range(n):
        s += '<a xmlns:p' + String(i) + '="u' + String(i) + '">'
    s += "<p" + String(n - 1) + ":z/>"
    for _ in range(n):
        s += "</a>"
    var d = parse(s)
    assert_equal(len(d), n + 1)
    assert_equal(d.ns(n), "u" + String(n - 1))


def test_namespace_bindings_restore_at_the_end_tag() raises:
    var d = parse('<r xmlns:p="u1"><a xmlns:p="u2"><p:x/></a><p:y/><b xmlns:q="u3"/></r>')
    assert_equal(d.ns(2), "u2")
    assert_equal(d.ns(3), "u1")
    var raised = False
    try:
        _ = parse('<r><b xmlns:q="u3"/><q:z/></r>')
    except:
        raised = True
    assert_true(raised, "q: must be out of scope after the self-closing <b/>")


def test_arxiv_atom_dom() raises:
    var s = open(_fixtures() + "/arxiv_1706.03762.atom", "r").read()
    var d = parse(s)
    var root = d.root()
    assert_equal(d.name(root), "feed")
    assert_equal(d.attr(root, "xmlns").value(), "http://www.w3.org/2005/Atom")
    var titles = d.children_named(root, "title")
    assert_equal(len(titles), 1)
    assert_equal(d.text(titles[0]), "arXiv Query: search_query=&id_list=1706.03762&start=0&max_results=1")
    var total = d.children_named(root, "totalResults")
    assert_equal(d.name(total[0]), "opensearch:totalResults")
    assert_equal(d.text(total[0]), "1")
    var entries = d.children_named(root, "entry")
    assert_equal(len(entries), 1)
    var e = entries[0]
    assert_equal(d.text(d.children_named(e, "title")[0]), "Attention Is All You Need")
    assert_equal(len(d.children_named(e, "author")), 8)
    var links = d.children_named(e, "link")
    assert_equal(len(links), 2)
    assert_equal(d.attr(links[1], "title").value(), "pdf")
    assert_equal(d.attr(links[1], "href").value(), "https://arxiv.org/pdf/1706.03762v7")
    var summary = d.text(d.children_named(e, "summary")[0])
    assert_true(summary.startswith("The dominant sequence transduction"))
    var names = d.child_local_names(e)
    assert_true(len(names) >= 8)


def test_entities_cdata_comments() raises:
    var d = parse("<?xml version='1.0'?><!-- c --><a x='1&amp;2'>&lt;hi&gt; &#65;&#x42;<![CDATA[<raw>]]><b/><!-- z --></a>")
    assert_equal(d.attr(0, "x").value(), "1&2")
    assert_equal(d.text(0), "<hi> AB<raw>")
    assert_equal(len(d.children(0)), 1)
    assert_equal(d.name(1), "b")


def test_text_split_around_children() raises:
    # Element text resumes after a child's text and attributes were pooled.
    var d = parse('<a>x<b k="v">y</b>z<c/>w</a>')
    assert_equal(d.text(0), "xzw")
    assert_equal(d.text(1), "y")
    assert_equal(d.attr(1, "k").value(), "v")
    assert_equal(len(d.children(0)), 2)
    assert_equal(d.parent(2), 0)


def test_line_end_and_attribute_normalization() raises:
    # XML 1.0 2.11 and 3.3.3; a character reference is never normalized.
    var d = parse("<a x='t\tn\nc\r\nz&#10;'>l\r\nm\rn<![CDATA[c\r\nd]]>&#13;</a>")
    assert_equal(d.attr(0, "x").value(), "t n c z\n")
    assert_equal(d.text(0), "l\nm\nnc\nd\r")


def test_attribute_namespaces_and_bom() raises:
    var d = parse('\ufeff<?xml version="1.0" encoding="UTF-8"?><r xmlns:p="urn:p" p:a="1" a="2" xml:lang="en"/>')
    assert_equal(d.attr_ns(0, String("urn:p"), "a").value(), "1")
    assert_equal(d.attr_ns(0, String(""), "a").value(), "2")
    assert_equal(d.attr_ns(0, String("http://www.w3.org/XML/1998/namespace"), "lang").value(), "en")
    assert_equal(d.attr(0, "p:a").value(), "1")


def test_xml_space_preserve() raises:
    var d = parse("<r><p xml:space='preserve'><b>a</b> <i>b</i><q xml:space='default'> </q></p><s> </s></r>")
    assert_equal(d.text(1), " ")       # kept under preserve
    assert_true(not d.has_text(4))      # reset by default
    assert_true(not d.has_text(5))      # outside: dropped as before


def test_html_entities_opt_in() raises:
    var raised = False
    try:
        _ = parse("<a>&nbsp;</a>")
    except:
        raised = True
    assert_true(raised, "&nbsp; must raise without an entity map")
    var ents = html_entities()
    assert_equal(len(ents), 2120)
    var d = parse("<a t='&eacute;'>x&nbsp;y&NotEqualTilde;&amp;</a>", ents)
    assert_equal(d.text(0), "x\u00a0y\u2242\u0338&")
    assert_equal(d.attr(0, "t").value(), "\u00e9")
    var mine: Dict[String, String] = {"co": "Example Corp"}
    assert_equal(parse("<a>&co;</a>", mine).text(0), "Example Corp")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
