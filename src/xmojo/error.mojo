# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Typed parse error: tokenizer/dom raise this instead of a bare `Error` so
# from_xml can surface exact position + context without string-parsing.
@fieldwise_init
struct XmlError(Copyable, Movable, Writable):
    var message: String
    var line: Int       # 1-based
    var col: Int         # 1-based, bytes
    var tag: String      # nearest open element name, "" at top level

    def write_to(self, mut writer: Some[Writer]):
        writer.write("xmojo: ", self.message, " at ", self.line, ":", self.col)
        if self.tag:
            writer.write(" in <", self.tag, ">")
