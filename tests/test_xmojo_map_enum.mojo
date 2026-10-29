# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
from std.utils import Variant
from std.testing import assert_equal, assert_true, TestSuite
from xmojo import ArmName
from xmojo import from_xml


def test_dict_from_children() raises:
    var m = from_xml[Dict[String, Int]]("<r><a>1</a><b>2</b></r>")
    assert_equal(m["a"], 1)
    assert_equal(m["b"], 2)
    assert_equal(len(m), 2)


@fieldwise_init
struct Item(Copyable, Defaultable, Movable):
    var attrs: Dict[String, String]

    def __init__(out self):
        self.attrs = Dict[String, String]()


def test_dict_from_attrs() raises:
    var it = from_xml[Item]('<item x="1" y="2"/>')
    assert_equal(it.attrs["x"], "1")
    assert_equal(it.attrs["y"], "2")
    assert_equal(len(it.attrs), 2)


struct Beta(ArmName, Copyable, Defaultable, Movable):
    comptime serde_arm_name: StaticString = "Beta"

    def __init__(out self):
        pass


@fieldwise_init
struct S(Copyable, Defaultable, Movable):
    var kind: Variant[Beta]

    def __init__(out self):
        self.kind = Variant[Beta](Beta())


def test_enum_decodes_known_arm() raises:
    var s = from_xml[S]('<s kind="Beta"/>')
    assert_true(s.kind.isa[Beta]())


def test_enum_unknown_arm_raises_with_message() raises:
    var raised = False
    try:
        _ = from_xml[S]('<s kind="Gamma"/>')
    except e:
        raised = True
        assert_true(String(e).find("enum") >= 0, String(e))
        assert_true(String(e).find("Gamma") >= 0, String(e))
    assert_true(raised, "expected DeserializationError")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
