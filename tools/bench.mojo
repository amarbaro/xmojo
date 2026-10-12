# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Benchmarks (build: mojo build -I src tools/bench.mojo -o .work/bench): `deep N` = N nested <a>, `wide N` = N sibling <a/> under one root,
# `obj N` = the wide document decoded with from_xml (parse + field reads), `rec N` = the same
# document streamed record by record (Records + from_xml per item), `ser N` = to_xml of N items, `file PATH N` = parse
# a real file N times (reported ms is the total).
from std.sys import argv
from std.time import perf_counter_ns
from xmojo import parse, from_xml, to_xml, Records


@fieldwise_init
struct A(Copyable, Defaultable, Movable):
    var x: Int
    var text: String

    def __init__(out self):
        self.x = 0
        self.text = ""


@fieldwise_init
struct R(Copyable, Defaultable, Movable):
    var a: List[A]

    def __init__(out self):
        self.a = List[A]()


def main() raises:
    var args = argv()
    var mode = String(args[1])
    if mode == "file":
        var text = open(String(args[2]), "r").read()
        var reps = Int(args[3])
        var t = perf_counter_ns()
        var count = 0
        for _ in range(reps):
            var d = parse(text)
            count += len(d.nodes)
        print(mode, reps, "nodes", count, "ms", Float64(perf_counter_ns() - t) / 1e6)
        return
    var n = Int(args[2])
    var s = String()
    if mode == "deep":
        for _ in range(n):
            s += "<a>"
        for _ in range(n):
            s += "</a>"
    else:
        s += "<r>"
        for _ in range(n):
            s += "<a x=\"1\">t</a>"
        s += "</r>"
    var t0 = perf_counter_ns()
    if mode == "ser":
        var r = R()
        for i in range(n):
            r.a.append(A(i, "t"))
        var t = perf_counter_ns()
        var xml = to_xml(r, "r")
        print(mode, n, "bytes", xml.byte_length(), "ms", Float64(perf_counter_ns() - t) / 1e6)
        return
    if mode == "rec":
        var it = Records(s, "a")
        var items = 0
        while True:
            var r = it.next()
            if not r:
                break
            items += from_xml[A](r.value()).x
        print(mode, n, "items", items, "ms", Float64(perf_counter_ns() - t0) / 1e6)
        return
    if mode == "obj":
        var r = from_xml[R](s)
        print(mode, n, "items", len(r.a), "ms", Float64(perf_counter_ns() - t0) / 1e6)
        return
    var d = parse(s)
    var ms = Float64(perf_counter_ns() - t0) / 1e6
    print(mode, n, "nodes", len(d.nodes), "bytes", s.byte_length(), "ms", ms)
