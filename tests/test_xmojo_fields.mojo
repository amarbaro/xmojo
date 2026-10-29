# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Field and struct modifiers through xmojo, both directions.
from std.testing import assert_equal, assert_true, TestSuite
from xmojo import Field, Rename, Skip, Defaulted
from xmojo import RenameAll, RenamePolicy, DenyUnknownFields
from xmojo import from_xml, to_xml


@fieldwise_init
struct User(Copyable, Defaultable, Movable):
    var name: Rename[String, "userName"]
    var debug: Skip[Bool]
    var retries: Defaulted[Int, 3]
    var email: Field[String, extra_names=List[String](["mail"])]

    def __init__(out self):
        self.name = Rename[String, "userName"]("")
        self.debug = Skip[Bool](False)
        self.retries = Defaulted[Int, 3](0)
        self.email = Field[String, extra_names=List[String](["mail"])]("")


@fieldwise_init
struct Config(Copyable, Defaultable, Movable, RenameAll, DenyUnknownFields):
    comptime FieldRenamePolicy = RenamePolicy.CamelCase
    var host_name: String

    def __init__(out self):
        self.host_name = ""


@fieldwise_init
struct Point(Copyable, Movable):   # not Defaultable: only trivially destructible fields
    var x: Int
    var ok: Bool


def test_rename_alias_default_skip() raises:
    var u = from_xml[User]('<u userName="ada" mail="a@b.c" debug="true"/>')
    assert_equal(u.name[], "ada")
    assert_equal(u.email[], "a@b.c")    # alias
    assert_equal(u.retries[], 3)        # absent: the declared default
    assert_true(not u.debug[])          # skipped: never read
    var out = to_xml(u, "u")
    assert_equal(out, '<u userName="ada" retries="3" email="a@b.c"/>')


def test_rename_all_and_deny_unknown() raises:
    assert_equal(from_xml[Config]('<c hostName="h"/>').host_name, "h")
    var raised = False
    try:
        _ = from_xml[Config]('<c hostName="h"><extra/></c>')
    except e:
        raised = True
        assert_true(String(e).find("extra") >= 0, String(e))
    assert_true(raised, "DenyUnknownFields must reject an unknown child")


def test_non_defaultable_struct() raises:
    var p = from_xml[Point]('<p x="2" ok="true"/>')
    assert_equal(p.x, 2)
    assert_true(p.ok)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
