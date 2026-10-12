# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# The README's Usage example, its comments turned into assertions. Keep the two in step.
from std.testing import assert_equal, assert_true, TestSuite
from xmojo import from_xml, to_xml, Records, parse


@fieldwise_init
struct Link(Copyable, Defaultable, Movable):
    var href: String
    var title: Optional[String]

    def __init__(out self):
        self.href = ""
        self.title = None


@fieldwise_init
struct Entry(Copyable, Defaultable, Movable):
    var title: String
    var link: List[Link]

    def __init__(out self):
        self.title = ""
        self.link = List[Link]()


def test_readme_usage() raises:
    var text = String('<entry><title>Hi</title><link href="a"/><link href="b" title="B"/></entry>')
    var e = from_xml[Entry](text)
    assert_equal(e.link[1].title.value(), "B")
    var xml = to_xml(e, "entry")
    var back = from_xml[Entry](xml)
    assert_equal(back.title, "Hi")
    assert_equal(len(back.link), 2)
    assert_true(not back.link[0].title)
    assert_equal(back.link[1].title.value(), "B")

    var it = Records(text, "link")
    var hrefs = List[String]()
    while True:
        var rec = it.next()
        if not rec:
            break
        hrefs.append(from_xml[Link](rec.value()).href)
    assert_equal(len(hrefs), 2)
    assert_equal(hrefs[1], "b")

    var d = parse(text)
    assert_equal(d.name(0), "entry")
    assert_equal(len(d.children(0)), 3)
    assert_equal(d.attr(3, "title").value(), "B")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
