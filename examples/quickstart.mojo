from xmojo import from_xml, to_xml, Records, parse


@fieldwise_init
struct Link(Copyable, Defaultable, Movable):
    var href: String                 # <- attribute href
    var title: Optional[String]      # <- attribute title, None if absent

    def __init__(out self):
        self.href = ""
        self.title = None


@fieldwise_init
struct Entry(Copyable, Defaultable, Movable):
    var title: String                # <- <title>text</title>
    var link: List[Link]             # <- every <link .../> child

    def __init__(out self):
        self.title = ""
        self.link = List[Link]()


def main() raises:
    var text = String('<entry><title>Hi</title><link href="a"/><link href="b" title="B"/></entry>')
    var e = from_xml[Entry](text)              # e.link[1].title.value() == "B"
    var back = from_xml[Entry](to_xml(e, "entry"))  # round trip: back.link[1].title == "B"

    var it = Records(text, "link")             # one <link> at a time, as standalone XML
    while True:
        var rec = it.next()
        if not rec:
            break
        print(from_xml[Link](rec.value()).href)

    var d = parse(text)                        # the tree: element 0 is the root
    print(d.name(0), len(d.children(0)), d.attr(3, "title").value())   # entry 3 B
