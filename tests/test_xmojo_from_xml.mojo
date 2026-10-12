# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
from std.testing import assert_equal, assert_true, TestSuite
from xmojo import from_xml, Records

from std.os import getenv


def _fixtures() -> String:
    """Fixture dir: tests/fixtures from the repository root, or $XMOJO_FIXTURES."""
    var v = getenv("XMOJO_FIXTURES")
    return v if v != "" else String("tests/fixtures")


@fieldwise_init
struct Link(Copyable, Defaultable, Movable):
    var href: String
    var rel: Optional[String]
    var title: Optional[String]

    def __init__(out self):
        self.href = ""
        self.rel = None
        self.title = None


@fieldwise_init
struct Author(Copyable, Defaultable, Movable):
    var name: String

    def __init__(out self):
        self.name = ""


@fieldwise_init
struct Entry(Copyable, Defaultable, Movable):
    var id: String
    var title: String
    var published: Optional[String]
    var summary: String
    var author: List[Author]
    var link: List[Link]

    def __init__(out self):
        self.id = ""
        self.title = ""
        self.published = None
        self.summary = ""
        self.author = List[Author]()
        self.link = List[Link]()


@fieldwise_init
struct Feed(Copyable, Defaultable, Movable):
    var title: String
    var totalResults: Optional[Int]
    var entry: List[Entry]

    def __init__(out self):
        self.title = ""
        self.totalResults = None
        self.entry = List[Entry]()


def test_arxiv_feed_from_xml() raises:
    var s = open(_fixtures() + "/arxiv_1706.03762.atom", "r").read()
    var f = from_xml[Feed](s)
    assert_equal(f.totalResults.value(), 1)
    assert_equal(len(f.entry), 1)
    ref e = f.entry[0]
    assert_equal(e.id, "http://arxiv.org/abs/1706.03762v7")
    assert_equal(e.title, "Attention Is All You Need")
    assert_equal(e.published.value(), "2017-06-12T17:57:34Z")
    assert_equal(len(e.author), 8)
    assert_equal(e.author[0].name, "Ashish Vaswani")
    assert_equal(len(e.link), 2)
    assert_equal(e.link[1].title.value(), "pdf")
    assert_equal(e.link[1].href, "https://arxiv.org/pdf/1706.03762v7")
    assert_true(e.link[0].title is None)
    assert_true(e.summary.startswith("The dominant sequence transduction"))


@fieldwise_init
struct Tag(Copyable, Defaultable, Movable):
    var term: String
    var text: Optional[String]

    def __init__(out self):
        self.term = ""
        self.text = None


@fieldwise_init
struct Small(Copyable, Defaultable, Movable):
    var n: Int
    var ok: Bool
    var ratio: Float64
    var tag: List[Tag]

    def __init__(out self):
        self.n = 0
        self.ok = False
        self.ratio = 0.0
        self.tag = List[Tag]()


def test_scalars_attrs_text() raises:
    var x = from_xml[Small]("<r><n> 42 </n><ok>true</ok><ratio>0.5</ratio><tag term='a'>hello</tag><tag term='b'/></r>")
    assert_equal(x.n, 42)
    assert_true(x.ok)
    assert_equal(x.ratio, 0.5)
    assert_equal(len(x.tag), 2)
    assert_equal(x.tag[0].term, "a")
    assert_equal(x.tag[0].text.value(), "hello")
    assert_true(x.tag[1].text is None)


@fieldwise_init
struct Clash(Copyable, Defaultable, Movable):
    var id: String
    var text: String

    def __init__(out self):
        self.id = ""
        self.text = ""


def test_attribute_wins_over_same_named_child() raises:
    # Field precedence is attribute, then child element, then text: a name bound
    # twice on the wire must not surface as DuplicateField.
    var c = from_xml[Clash]('<e id="attr"><id>child</id><text>kid</text>body</e>')
    assert_equal(c.id, "attr")
    assert_equal(c.text, "kid")


@fieldwise_init
struct Lang(Copyable, Defaultable, Movable):
    var lang: String

    def __init__(out self):
        self.lang = ""


def test_prefixed_attribute_binds_by_local_name() raises:
    assert_equal(from_xml[Lang]('<e xmlns:x="urn:x" xml:lang="en"/>').lang, "en")


def test_records_stream_with_inherited_namespaces() raises:
    # The entry uses arxiv:primary_category, declared only on <feed>: the record must carry it.
    var text = open(_fixtures() + "/arxiv_1706.03762.atom", "r").read()
    var it = Records(text, "entry")
    var n = 0
    while True:
        var rec = it.next()
        if not rec:
            break
        assert_true(rec.value().find('xmlns:arxiv="http://arxiv.org/schemas/atom"') > 0)
        assert_equal(from_xml[Entry](rec.value()).title, "Attention Is All You Need")
        n += 1
    assert_equal(n, 1)
    var it2 = Records("<r xmlns:p='u'><p:a x='1'><p:a/></p:a><b/><a xmlns:p='v'/></r>", "a")
    assert_equal(it2.next().value(), "<p:a xmlns:p='u' x='1'><p:a/></p:a>")
    assert_equal(it2.next().value(), "<a xmlns:p='v'/>")
    assert_true(not it2.next())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
