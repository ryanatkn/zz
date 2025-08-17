const std = @import("std");

// ============================================================================
// Core Types - Main public API
// ============================================================================

/// Complete grammar that can parse input
pub const Grammar = @import("grammar.zig").Grammar;

/// Builder for constructing grammars with fluent API
pub const Builder = @import("builder.zig").Builder;

// ============================================================================
// Rule System - Basic building blocks
// ============================================================================

pub const Rule = @import("rule.zig").Rule;
pub const Terminal = @import("rule.zig").Terminal;
pub const Sequence = @import("rule.zig").Sequence;
pub const Choice = @import("rule.zig").Choice;
pub const Optional = @import("rule.zig").Optional;
pub const Repeat = @import("rule.zig").Repeat;
pub const Repeat1 = @import("rule.zig").Repeat1;

// ============================================================================
// Extended Rules - For building with references
// ============================================================================

pub const ExtendedRules = @import("extended_rules.zig");
pub const ExtendedRule = ExtendedRules.ExtendedRule;
pub const RuleRef = ExtendedRules.RuleRef;

// ============================================================================
// Helper Functions - Convenient rule creation
// ============================================================================

// Basic rule helpers
pub const rule = @import("rule.zig");
pub const terminal = rule.terminal;
pub const sequence = rule.sequence;
pub const choice = rule.choice;
pub const optional = rule.optional;
pub const repeat = rule.repeat;
pub const repeat1 = rule.repeat1;

// Extended rule helpers (for builder)
pub const extended = ExtendedRules;
pub const ref = ExtendedRules.ref;

// ============================================================================
// Testing Utilities
// ============================================================================

pub const TestFramework = @import("test_framework.zig");
pub const TestContext = TestFramework.TestContext;
pub const MatchResult = TestFramework.MatchResult;
pub const TestHelpers = TestFramework.TestHelpers;

// ============================================================================
// Internal Modules - Available but typically not needed by users
// ============================================================================

pub const Validation = @import("validation.zig");
pub const Resolver = @import("resolver.zig");