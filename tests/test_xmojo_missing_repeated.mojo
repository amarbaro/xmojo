# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# A declared List field whose element never appears on the wire decodes as an
# empty list; a declared Optional as None; a required scalar still raises
# MissingField ("missing field: <name>"). Shape taken from NCBI
# esearch's zero-hit answer: `<IdList/>`.
from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from xmojo import from_xml


@fieldwise_init
struct IdList(Copyable, Defaultable, Movable):
    var Id: List[String]

    def __init__(out self):
        self.Id = List[String]()


@fieldwise_init
struct Result(Copyable, Defaultable, Movable):
    var Count: String
    var IdList: IdList
    var Warning: Optional[String]

    def __init__(out self):
        self.Count = ""
        self.IdList = IdList()
        self.Warning = None


@fieldwise_init
struct Strict(Copyable, Defaultable, Movable):
    var Count: String
    var RetMax: String

    def __init__(out self):
        self.Count = ""
        self.RetMax = ""


def test_empty_element_gives_empty_list() raises:
    var r = from_xml[Result]("<eSearchResult><Count>0</Count><IdList/></eSearchResult>")
    assert_equal(r.Count, "0")
    assert_equal(len(r.IdList.Id), 0)
    assert_true(not r.Warning)


def test_absent_required_struct_still_missing() raises:
    with assert_raises(contains="missing field: IdList"):
        _ = from_xml[Result]("<eSearchResult><Count>0</Count></eSearchResult>")


def test_present_ids_still_decode() raises:
    var r = from_xml[Result]("<r><Count>2</Count><IdList><Id>1</Id><Id>2</Id></IdList></r>")
    assert_equal(r.IdList.Id, ["1", "2"])


def test_required_scalar_still_missing() raises:
    with assert_raises(contains="missing field: RetMax"):
        _ = from_xml[Strict]("<r><Count>0</Count></r>")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
