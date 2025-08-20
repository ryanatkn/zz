const std = @import("std");
const Grammar = @import("../../grammar/mod.zig").Grammar;
const Rule = @import("../../grammar/mod.zig").Rule;
const Terminal = @import("../../grammar/mod.zig").Terminal;
const Sequence = @import("../../grammar/mod.zig").Sequence;
const Choice = @import("../../grammar/mod.zig").Choice;
const Optional = @import("../../grammar/mod.zig").Optional;
const Repeat = @import("../../grammar/mod.zig").Repeat;
const Repeat1 = @import("../../grammar/mod.zig").Repeat1;
const ParseContext = @import("context.zig").ParseContext;
pub const ParseError = @import("context.zig").ParseError;

pub const ParserError = error{
    ParseFailed,
    OutOfMemory,
};

pub const ParseOptions = struct {
    max_depth: u32 = 1000,
    enable_recovery: bool = true,
    track_positions: bool = true,
    boundary: ?@import("../structural/mod.zig").ParseBoundary = null,
    tokens: ?[]const @import("../foundation/types/token.zig").Token = null,
};

pub const ParseResult = union(enum) {
    success: ParseNode,
    failure: []const ParseError,

    pub fn isSuccess(self: ParseResult) bool {
        return switch (self) {
            .success => true,
            .failure => false,
        };
    }
};

/// Temporary parse node until we have full AST module
pub const ParseNode = struct {
    rule_id: u16,
    text: []const u8,
    start_position: usize,
    end_position: usize,
    children: []ParseNode,

    pub fn deinit(self: ParseNode, allocator: std.mem.Allocator) void {
        for (self.children) |child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }
};

/// Simple recursive descent parser
pub const Parser = struct {
    allocator: std.mem.Allocator,
    grammar: Grammar,

    pub fn init(allocator: std.mem.Allocator, grammar: Grammar) Parser {
        return .{
            .allocator = allocator,
            .grammar = grammar,
        };
    }

    pub fn deinit(self: *Parser) void {
        _ = self;
        // Parser doesn't own the grammar
    }

    /// Parse input with additional context options
    pub fn parseWithContext(self: Parser, input: []const u8, options: ParseOptions) !ParseResult {
        _ = options;
        return self.parse(input);
    }

    /// Parse input using the grammar's start rule
    pub fn parse(self: Parser, input: []const u8) !ParseResult {
        var context = ParseContext.init(self.allocator, input);
        defer context.deinit();

        const start_rule_id = self.grammar.start_rule_id;
        const start_rule = self.grammar.rules.get(start_rule_id) orelse {
            try context.addError("Start rule not found in grammar");
            return ParseResult{ .failure = context.errors.items };
        };
        if (self.parseRule(start_rule, start_rule_id, &context)) |node| {
            // Check if we consumed all input
            if (!context.isAtEnd()) {
                try context.addError("Unexpected input after parsing completed");
                return ParseResult{ .failure = context.errors.items };
            }
            return ParseResult{ .success = node };
        } else |err| {
            switch (err) {
                error.ParseFailed => {
                    if (context.errors.items.len == 0) {
                        try context.addError("Parse failed without specific error");
                    }
                    return ParseResult{ .failure = context.errors.items };
                },
                else => return err,
            }
        }
    }

    /// Parse a specific rule
    fn parseRule(self: Parser, rule: Rule, rule_id: u16, context: *ParseContext) ParserError!ParseNode {
        switch (rule) {
            .terminal => |terminal_rule| {
                return self.parseTerminal(terminal_rule, rule_id, context);
            },
            .sequence => |sequence_rule| {
                return self.parseSequence(sequence_rule, rule_id, context);
            },
            .choice => |choice_rule| {
                return self.parseChoice(choice_rule, rule_id, context);
            },
            .optional => |optional_rule| {
                return self.parseOptional(optional_rule, rule_id, context);
            },
            .repeat => |repeat_rule| {
                return self.parseRepeat(repeat_rule, rule_id, context);
            },
            .repeat1 => |repeat1_rule| {
                return self.parseRepeat1(repeat1_rule, rule_id, context);
            },
        }
    }

    fn parseTerminal(self: Parser, terminal: Terminal, rule_id: u16, context: *ParseContext) ParserError!ParseNode {
        _ = self;
        const start_pos = context.position;
        const remaining = context.remaining();

        if (std.mem.startsWith(u8, remaining, terminal.literal)) {
            context.advance(terminal.literal.len);
            const end_pos = context.position;

            return ParseNode{
                .rule_id = rule_id,
                .text = context.getTextBetween(start_pos, end_pos),
                .start_position = start_pos,
                .end_position = end_pos,
                .children = &[_]ParseNode{},
            };
        } else {
            return ParserError.ParseFailed;
        }
    }

    fn parseSequence(self: Parser, sequence: Sequence, rule_id: u16, context: *ParseContext) ParserError!ParseNode {
        const start_pos = context.position;
        var children = std.ArrayList(ParseNode).init(self.allocator);
        defer children.deinit();

        for (sequence.rules) |child_rule| {
            const child_node = self.parseRule(child_rule, rule_id, context) catch |err| {
                // Clean up any successfully parsed children
                for (children.items) |child| {
                    child.deinit(self.allocator);
                }
                return err;
            };
            try children.append(child_node);
        }

        const end_pos = context.position;
        const children_slice = try self.allocator.dupe(ParseNode, children.items);

        return ParseNode{
            .rule_id = rule_id,
            .text = context.getTextBetween(start_pos, end_pos),
            .start_position = start_pos,
            .end_position = end_pos,
            .children = children_slice,
        };
    }

    fn parseChoice(self: Parser, choice: Choice, rule_id: u16, context: *ParseContext) ParserError!ParseNode {
        for (choice.choices) |alternative| {
            const mark = context.mark();
            if (self.parseRule(alternative, rule_id, context)) |node| {
                return node;
            } else |_| {
                context.reset(mark);
                continue;
            }
        }

        return ParserError.ParseFailed;
    }

    fn parseOptional(self: Parser, optional: Optional, rule_id: u16, context: *ParseContext) ParserError!ParseNode {
        const start_pos = context.position;
        const mark = context.mark();

        if (self.parseRule(optional.rule.*, rule_id, context)) |child_node| {
            const end_pos = context.position;
            const children_slice = try self.allocator.dupe(ParseNode, &[_]ParseNode{child_node});

            return ParseNode{
                .rule_id = rule_id,
                .text = context.getTextBetween(start_pos, end_pos),
                .start_position = start_pos,
                .end_position = end_pos,
                .children = children_slice,
            };
        } else |_| {
            // Optional failed, reset and return empty match
            context.reset(mark);
            return ParseNode{
                .rule_id = rule_id,
                .text = "",
                .start_position = start_pos,
                .end_position = start_pos,
                .children = &[_]ParseNode{},
            };
        }
    }

    fn parseRepeat(self: Parser, repeat: Repeat, rule_id: u16, context: *ParseContext) ParserError!ParseNode {
        const start_pos = context.position;
        var children = std.ArrayList(ParseNode).init(self.allocator);
        defer children.deinit();

        while (true) {
            const mark = context.mark();
            if (self.parseRule(repeat.rule.*, rule_id, context)) |child_node| {
                try children.append(child_node);
            } else |_| {
                context.reset(mark);
                break;
            }
        }

        const end_pos = context.position;
        const children_slice = try self.allocator.dupe(ParseNode, children.items);

        return ParseNode{
            .rule_id = rule_id,
            .text = context.getTextBetween(start_pos, end_pos),
            .start_position = start_pos,
            .end_position = end_pos,
            .children = children_slice,
        };
    }

    fn parseRepeat1(self: Parser, repeat1: Repeat1, rule_id: u16, context: *ParseContext) ParserError!ParseNode {
        const start_pos = context.position;
        var children = std.ArrayList(ParseNode).init(self.allocator);
        defer children.deinit();

        // Must match at least once
        if (self.parseRule(repeat1.rule.*, rule_id, context)) |first_child| {
            try children.append(first_child);
        } else |_| {
            return ParserError.ParseFailed;
        }

        // Then match as many times as possible
        while (true) {
            const mark = context.mark();
            if (self.parseRule(repeat1.rule.*, rule_id, context)) |child_node| {
                try children.append(child_node);
            } else |_| {
                context.reset(mark);
                break;
            }
        }

        const end_pos = context.position;
        const children_slice = try self.allocator.dupe(ParseNode, children.items);

        return ParseNode{
            .rule_id = rule_id,
            .text = context.getTextBetween(start_pos, end_pos),
            .start_position = start_pos,
            .end_position = end_pos,
            .children = children_slice,
        };
    }
};
