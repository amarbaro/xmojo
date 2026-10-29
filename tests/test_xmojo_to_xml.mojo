# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
from std.utils import Variant
from std.testing import assert_equal, assert_true, TestSuite
from xmojo import ArmName
from xmojo import from_xml, to_xml, parse


@fieldwise_init
struct Link(Copyable, Defaultable, Movable):
    var href: String
    var text: String

    def __init__(out self):
        self.href = ""
        self.text = ""


struct Beta(ArmName, Copyable, Defaultable, Movable):
    comptime serde_arm_name: StaticString = "Beta"

    def __init__(out self):
        pass


@fieldwise_init
struct Entry(Copyable, Defaultable, Movable):
    var id: Int
    var score: Float64
    var ok: Bool
    var title: Optional[String]
    var note: Optional[String]
    var link: List[Link]
    var tags: List[String]
    var kind: Variant[Beta]
    var attrs: Dict[String, String]

    def __init__(out self):
        self.id = 0
        self.score = 0
        self.ok = False
        self.title = None
        self.note = None
        self.link = List[Link]()
        self.tags = List[String]()
        self.kind = Variant[Beta](Beta())
        self.attrs = Dict[String, String]()


def test_round_trip() raises:
    var e = Entry()
    e.id = 7
    e.score = 2.5
    e.ok = True
    e.title = String('a<b & "c"\tx\r\ny')
    e.link = [Link("u1", "one & two"), Link("u2", "")]
    e.tags = ["x", "y"]
    e.attrs = {"lang": "en"}
    var s = to_xml(e, "entry")
    var b = from_xml[Entry](s)
    assert_equal(b.id, 7)
    assert_equal(b.score, 2.5)
    assert_true(b.ok)
    assert_equal(b.title.value(), 'a<b & "c"\tx\r\ny')
    assert_true(not b.note)
    assert_equal(len(b.link), 2)
    assert_equal(b.link[0].text, "one & two")
    assert_equal(b.link[1].href, "u2")
    assert_equal(b.link[1].text, "")
    assert_equal(len(b.tags), 2)
    assert_equal(b.tags[1], "y")
    assert_true(b.kind.isa[Beta]())
    assert_equal(b.attrs["lang"], "en")


def test_shape() raises:
    # Scalars as attributes, `text` as element text, lists as repeated children, None omitted.
    assert_equal(to_xml(Link("h", "t"), "link"), '<link href="h">t</link>')
    assert_equal(to_xml(Link("h", ""), "link"), '<link href="h"/>')
    _ = parse(to_xml(Entry(), "entry"))   # well-formed even when everything is empty


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
