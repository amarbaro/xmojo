# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
from std.testing import assert_equal, assert_true, TestSuite
from std.time import perf_counter_ns
from xmojo import parse, XmlError

from std.os import getenv


def _fixtures() -> String:
    """Fixture dir: tests/fixtures from the repository root, or $XMOJO_FIXTURES."""
    var v = getenv("XMOJO_FIXTURES")
    return v if v != "" else String("tests/fixtures")



def _read(path: String) raises -> String:
    return open(path, "r").read()


def test_mismatched_end_tag_position() raises:
    var raised = False
    try:
        _ = parse("<a>\n  <b>\n</a>")
    except e:
        raised = True
        assert_equal(e.line, 3)
        assert_equal(e.col, 1)
        assert_equal(e.tag, "b")
        assert_true(String(e).find("mismatched end tag </a>") >= 0, String(e))
    assert_true(raised, "expected XmlError")


def test_unquoted_attribute_expects_quote() raises:
    var raised = False
    try:
        _ = parse("<a attr=oops/>")
    except e:
        raised = True
        assert_equal(e.line, 1)
        assert_true(String(e).find("expected quote") >= 0, String(e))
    assert_true(raised, "expected XmlError")


def test_bad_fixtures_raise_typed_errors() raises:
    var names: List[String] = [
        "unclosed_element.xml",
        "stray_end_tag.xml",
        "unterminated_attribute.xml",
        "unterminated_comment.xml",
        "unterminated_cdata.xml",
        "bad_entity_hex.xml",
        "unknown_entity.xml",
        "lt_in_text.xml",
        "empty_input.xml",
        "whitespace_only.xml",
        "digit_tag_name.xml",
        "duplicate_attribute.xml",
        "one_mb_unclosed.xml",
    ]
    for name in names:
        var s = _read(_fixtures() + "/bad/" + name)
        var raised = False
        try:
            _ = parse(s)
        except e:
            raised = True
            assert_true(e.line >= 1, name)
        assert_true(raised, "expected XmlError for " + name)


def test_depth_10000_parses_without_overflow() raises:
    var s = _read(_fixtures() + "/bad/" + "depth_10000.xml")
    var t0 = perf_counter_ns()
    var d = parse(s)
    var elapsed_ms = Int(perf_counter_ns() - t0) // 1_000_000
    assert_true(elapsed_ms < 2000, "depth 10000 took " + String(elapsed_ms) + "ms")
    assert_equal(len(d.nodes), 10000)


def test_oracle_found_malformed_raises() raises:
    # Each was accepted before the expat differential (tools/oracle.py) flagged it.
    var cases: List[String] = [
        "<a b='<'/>", "<a>&</a>", "<a>&#1;</a>", "<a>&#xD800;</a>", "<a x='1'y='2'/>",
        "<a/><b/>", "<a/>x", "<a><!X></a>", "<?xml verson='1.0'?><a/>",
        "<?xml version='1.0'<?><a/>", "<?xml version='10'?><a/>", "<p:/>", "<a&b/>",
        "<?x<y?><a/>", "<a -b='1'/>", "<p:a:b xmlns:p='u'/>", "<a q:x='1'/>",
        "<?xml version='1.0' encoding='ISO-8859-1'?><a/>", "<?xml version='1.0' standalone='maybe'?><a/>",
    ]
    for c in cases:
        var raised = False
        try:
            _ = parse(c)
        except:
            raised = True
        assert_true(raised, "expected XmlError for " + c)


def test_message_names_the_open_element_only_when_there_is_one() raises:
    try:
        _ = parse("<a><b></a>")
    except e:
        assert_equal(String(e), "xmojo: mismatched end tag </a>, open <b> at 1:7 in <b>")
    try:
        _ = parse("<a/><b/>")
    except e:
        assert_equal(String(e), "xmojo: content after the root element at 1:5")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
