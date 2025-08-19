const std = @import("std");

/// HTML language-specific patterns
pub const Patterns = struct {
    // Void elements (self-closing, no content)
    pub const void_elements = [_][]const u8{
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "param",
        "source",
        "track",
        "wbr",
    };

    // Block-level elements
    pub const block_elements = [_][]const u8{
        "address", "article",  "aside",      "blockquote",
        "canvas",  "dd",       "div",        "dl",
        "dt",      "fieldset", "figcaption", "figure",
        "footer",  "form",     "h1",         "h2",
        "h3",      "h4",       "h5",         "h6",
        "header",  "hr",       "li",         "main",
        "nav",     "noscript", "ol",         "p",
        "pre",     "section",  "table",      "tfoot",
        "ul",      "video",
    };

    // Inline elements
    pub const inline_elements = [_][]const u8{
        "a",     "abbr",     "acronym", "b",
        "bdo",   "big",      "br",      "button",
        "cite",  "code",     "dfn",     "em",
        "i",     "img",      "input",   "kbd",
        "label", "map",      "object",  "output",
        "q",     "samp",     "script",  "select",
        "small", "span",     "strong",  "sub",
        "sup",   "textarea", "time",    "tt",
        "var",
    };

    // Common attributes
    pub const global_attributes = [_][]const u8{
        "id",
        "class",
        "style",
        "title",
        "lang",
        "dir",
        "tabindex",
        "accesskey",
        "contenteditable",
        "hidden",
        "data-",
        "aria-",
        "role",
    };

    // Event attributes
    pub const event_attributes = [_][]const u8{
        "onclick",          "ondblclick",       "onmousedown", "onmouseup",
        "onmouseover",      "onmousemove",      "onmouseout",  "onmouseenter",
        "onmouseleave",     "onkeydown",        "onkeypress",  "onkeyup",
        "onfocus",          "onblur",           "onchange",    "onsubmit",
        "onreset",          "onload",           "onunload",    "onresize",
        "onscroll",         "onerror",          "onabort",     "oncanplay",
        "oncanplaythrough", "ondurationchange", "onemptied",   "onended",
        "onloadeddata",     "onloadedmetadata", "onloadstart", "onpause",
        "onplay",           "onplaying",        "onprogress",  "onratechange",
        "onseeked",         "onseeking",        "onstalled",   "onsuspend",
        "ontimeupdate",     "onvolumechange",   "onwaiting",
    };

    // Meta tag names
    pub const meta_names = [_][]const u8{
        "viewport",
        "description",
        "keywords",
        "author",
        "robots",
        "generator",
        "application-name",
        "theme-color",
        "color-scheme",
        "referrer",
    };

    // Link rel values
    pub const link_rel_values = [_][]const u8{
        "stylesheet",
        "icon",
        "canonical",
        "alternate",
        "author",
        "dns-prefetch",
        "preconnect",
        "prefetch",
        "preload",
        "prerender",
        "manifest",
        "apple-touch-icon",
    };

    // Input types
    pub const input_types = [_][]const u8{
        "text",   "password",       "email",  "url",
        "tel",    "number",         "range",  "date",
        "time",   "datetime-local", "month",  "week",
        "color",  "file",           "hidden", "image",
        "button", "reset",          "submit", "checkbox",
        "radio",  "search",
    };

    // Check if an element is void (self-closing)
    pub fn isVoidElement(tag_name: []const u8) bool {
        for (void_elements) |elem| {
            if (std.mem.eql(u8, tag_name, elem)) {
                return true;
            }
        }
        return false;
    }

    // Check if an element is block-level
    pub fn isBlockElement(tag_name: []const u8) bool {
        for (block_elements) |elem| {
            if (std.mem.eql(u8, tag_name, elem)) {
                return true;
            }
        }
        return false;
    }

    // Check if an element is inline
    pub fn isInlineElement(tag_name: []const u8) bool {
        for (inline_elements) |elem| {
            if (std.mem.eql(u8, tag_name, elem)) {
                return true;
            }
        }
        return false;
    }

    // Check if an attribute is global
    pub fn isGlobalAttribute(attr_name: []const u8) bool {
        for (global_attributes) |attr| {
            if (std.mem.eql(u8, attr_name, attr)) {
                return true;
            }
            // Check for data- and aria- prefixes
            if (std.mem.endsWith(u8, attr, "-")) {
                if (std.mem.startsWith(u8, attr_name, attr)) {
                    return true;
                }
            }
        }
        return false;
    }

    // Check if an attribute is an event handler
    pub fn isEventAttribute(attr_name: []const u8) bool {
        for (event_attributes) |attr| {
            if (std.mem.eql(u8, attr_name, attr)) {
                return true;
            }
        }
        return false;
    }

    // Check if a line contains an HTML tag
    pub fn containsTag(line: []const u8) bool {
        return std.mem.indexOf(u8, line, "<") != null and
            std.mem.indexOf(u8, line, ">") != null;
    }

    // Check if a line contains an opening tag
    pub fn isOpeningTag(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        return std.mem.startsWith(u8, trimmed, "<") and
            !std.mem.startsWith(u8, trimmed, "</") and
            !std.mem.startsWith(u8, trimmed, "<!") and
            std.mem.endsWith(u8, trimmed, ">");
    }

    // Check if a line contains a closing tag
    pub fn isClosingTag(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        return std.mem.startsWith(u8, trimmed, "</") and
            std.mem.endsWith(u8, trimmed, ">");
    }

    // Check if a line contains a DOCTYPE declaration
    pub fn isDoctype(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        const lower = std.ascii.lowerString(trimmed, trimmed);
        return std.mem.startsWith(u8, lower, "<!doctype");
    }

    // Check if a line contains a comment
    pub fn isComment(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        return std.mem.startsWith(u8, trimmed, "<!--") or
            (std.mem.indexOf(u8, trimmed, "<!--") != null and
                std.mem.indexOf(u8, trimmed, "-->") != null);
    }

    // Extract tag name from a tag string
    pub fn extractTagName(tag: []const u8) ?[]const u8 {
        var start: usize = 0;
        if (std.mem.startsWith(u8, tag, "</")) {
            start = 2;
        } else if (std.mem.startsWith(u8, tag, "<")) {
            start = 1;
        } else {
            return null;
        }

        var end = start;
        while (end < tag.len) : (end += 1) {
            const c = tag[end];
            if (c == ' ' or c == '>' or c == '/' or c == '\t' or c == '\n') {
                break;
            }
        }

        return if (end > start) tag[start..end] else null;
    }

    // Check if a value is a valid input type
    pub fn isValidInputType(type_value: []const u8) bool {
        for (input_types) |input_type| {
            if (std.mem.eql(u8, type_value, input_type)) {
                return true;
            }
        }
        return false;
    }
};

test "HTML patterns - void element detection" {
    try std.testing.expect(Patterns.isVoidElement("img"));
    try std.testing.expect(Patterns.isVoidElement("br"));
    try std.testing.expect(Patterns.isVoidElement("input"));
    try std.testing.expect(!Patterns.isVoidElement("div"));
    try std.testing.expect(!Patterns.isVoidElement("span"));
}

test "HTML patterns - block vs inline detection" {
    try std.testing.expect(Patterns.isBlockElement("div"));
    try std.testing.expect(Patterns.isBlockElement("p"));
    try std.testing.expect(!Patterns.isBlockElement("span"));

    try std.testing.expect(Patterns.isInlineElement("span"));
    try std.testing.expect(Patterns.isInlineElement("a"));
    try std.testing.expect(!Patterns.isInlineElement("div"));
}

test "HTML patterns - tag detection" {
    try std.testing.expect(Patterns.containsTag("<div>content</div>"));
    try std.testing.expect(Patterns.isOpeningTag("<div>"));
    try std.testing.expect(Patterns.isClosingTag("</div>"));
    try std.testing.expect(!Patterns.isOpeningTag("</div>"));
    try std.testing.expect(!Patterns.isClosingTag("<div>"));
}

test "HTML patterns - attribute detection" {
    try std.testing.expect(Patterns.isGlobalAttribute("id"));
    try std.testing.expect(Patterns.isGlobalAttribute("class"));
    try std.testing.expect(Patterns.isGlobalAttribute("data-id"));
    try std.testing.expect(Patterns.isGlobalAttribute("aria-label"));
    try std.testing.expect(!Patterns.isGlobalAttribute("href"));

    try std.testing.expect(Patterns.isEventAttribute("onclick"));
    try std.testing.expect(Patterns.isEventAttribute("onload"));
    try std.testing.expect(!Patterns.isEventAttribute("class"));
}

test "HTML patterns - extract tag name" {
    try std.testing.expectEqualStrings("div", Patterns.extractTagName("<div>").?);
    try std.testing.expectEqualStrings("div", Patterns.extractTagName("</div>").?);
    try std.testing.expectEqualStrings("input", Patterns.extractTagName("<input type='text'>").?);
    try std.testing.expect(Patterns.extractTagName("not a tag") == null);
}

test "HTML patterns - input type validation" {
    try std.testing.expect(Patterns.isValidInputType("text"));
    try std.testing.expect(Patterns.isValidInputType("email"));
    try std.testing.expect(Patterns.isValidInputType("checkbox"));
    try std.testing.expect(!Patterns.isValidInputType("invalid"));
}
