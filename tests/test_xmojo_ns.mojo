# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
from std.testing import assert_equal, assert_true, TestSuite
from std.time import perf_counter_ns
from xmojo import parse

from std.os import getenv


def _fixtures() -> String:
    """Fixture dir: tests/fixtures from the repository root, or $XMOJO_FIXTURES."""
    var v = getenv("XMOJO_FIXTURES")
    return v if v != "" else String("tests/fixtures")


def test_arxiv_atom_namespaces() raises:
    var s = open(_fixtures() + "/arxiv_1706.03762.atom", "r").read()
    var d = parse(s)
    var root = d.root()
    assert_equal(d.ns(root), "http://www.w3.org/2005/Atom")

    var entries = d.children_named(root, "entry")
    var e = entries[0]
    var primaries = d.children_named(e, "primary_category")
    assert_equal(len(primaries), 1)
    var pc = primaries[0]
    assert_equal(d.prefix(pc), "arxiv")
    assert_equal(d.ns(pc), "http://arxiv.org/schemas/atom")

    var total = d.children_ns(root, "http://a9.com/-/spec/opensearch/1.1/", "totalResults")
    assert_equal(len(total), 1)
    assert_equal(d.text(total[0]), "1")


def test_undeclared_prefix_raises() raises:
    var raised = False
    try:
        _ = parse("<x:a/>")
    except e:
        raised = True
        assert_true(String(e).find("x") >= 0, String(e))
    assert_true(raised, "expected XmlError")


def test_shared_scope_no_copy_at_scale() raises:
    """50 000 siblings under one namespaced root: sharing the parent's scope index
    (instead of copying its Dict per child) keeps this well under a second."""
    var n = 50_000
    var parts = List[String]()
    parts.append('<r xmlns="urn:x">')
    for _ in range(n):
        parts.append("<a/>")
    parts.append("</r>")
    var s = String("").join(parts)
    var t0 = perf_counter_ns()
    var d = parse(s)
    var elapsed_ms = Int(perf_counter_ns() - t0) // 1_000_000
    assert_true(elapsed_ms < 500, "50000 siblings took " + String(elapsed_ms) + "ms")
    assert_equal(len(d.children(d.root())), n)
    assert_equal(d.ns(d.children(d.root())[0]), "urn:x")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
