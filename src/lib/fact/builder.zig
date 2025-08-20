const std = @import("std");
const Fact = @import("fact.zig").Fact;
const FactId = @import("fact.zig").FactId;
const Predicate = @import("predicate.zig").Predicate;
const Value = @import("value.zig").Value;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const Span = @import("../span/mod.zig").Span;
const packSpan = @import("../span/mod.zig").packSpan;

/// Fluent builder for constructing facts
/// Provides a DSL for easy fact creation
pub const Builder = struct {
    id: FactId,
    subject: ?PackedSpan,
    predicate: ?Predicate,
    object: Value,
    confidence: f16,
    
    /// Start building a new fact
    pub fn new() Builder {
        return .{
            .id = 0,
            .subject = null,
            .predicate = null,
            .object = Value.fromNone(),
            .confidence = 1.0,
        };
    }
    
    /// Set the fact ID
    pub fn withId(self: Builder, id: FactId) Builder {
        var b = self;
        b.id = id;
        return b;
    }
    
    /// Set the subject span (already packed)
    pub fn withSubject(self: Builder, subject: PackedSpan) Builder {
        var b = self;
        b.subject = subject;
        return b;
    }
    
    /// Set the subject span (unpacked - will be packed)
    pub fn withSpan(self: Builder, span: Span) Builder {
        var b = self;
        b.subject = packSpan(span);
        return b;
    }
    
    /// Set the subject span from start and end positions
    pub fn withRange(self: Builder, start: u32, end: u32) Builder {
        return self.withSpan(Span.init(start, end));
    }
    
    /// Set the predicate
    pub fn withPredicate(self: Builder, predicate: Predicate) Builder {
        var b = self;
        b.predicate = predicate;
        return b;
    }
    
    /// Shorthand for common predicates
    pub fn isToken(self: Builder) Builder {
        return self.withPredicate(.is_token);
    }
    
    pub fn hasText(self: Builder) Builder {
        return self.withPredicate(.has_text);
    }
    
    pub fn isBoundary(self: Builder) Builder {
        return self.withPredicate(.is_boundary);
    }
    
    pub fn definesSymbol(self: Builder) Builder {
        return self.withPredicate(.defines_symbol);
    }
    
    pub fn referencesSymbol(self: Builder) Builder {
        return self.withPredicate(.references_symbol);
    }
    
    pub fn hasError(self: Builder) Builder {
        return self.withPredicate(.has_error);
    }
    
    /// Set the object value
    pub fn withObject(self: Builder, object: Value) Builder {
        var b = self;
        b.object = object;
        return b;
    }
    
    /// Set object to a number
    pub fn withNumber(self: Builder, number: i64) Builder {
        return self.withObject(Value.fromNumber(number));
    }
    
    /// Set object to an unsigned number
    pub fn withUint(self: Builder, uint: u64) Builder {
        return self.withObject(Value.fromUint(uint));
    }
    
    /// Set object to a float
    pub fn withFloat(self: Builder, float: f64) Builder {
        return self.withObject(Value.fromFloat(float));
    }
    
    /// Set object to a boolean
    pub fn withBool(self: Builder, boolean: bool) Builder {
        return self.withObject(Value.fromBool(boolean));
    }
    
    /// Set object to a span
    pub fn withObjectSpan(self: Builder, span: PackedSpan) Builder {
        return self.withObject(Value.fromSpan(span));
    }
    
    /// Set object to an atom ID
    pub fn withAtom(self: Builder, atom: u32) Builder {
        return self.withObject(Value.fromAtom(atom));
    }
    
    /// Set object to reference another fact
    pub fn withFactRef(self: Builder, fact_id: FactId) Builder {
        return self.withObject(Value.fromFact(fact_id));
    }
    
    /// Set the confidence level
    pub fn withConfidence(self: Builder, confidence: f16) Builder {
        var b = self;
        b.confidence = confidence;
        return b;
    }
    
    /// Set confidence to certain (1.0)
    pub fn certain(self: Builder) Builder {
        return self.withConfidence(1.0);
    }
    
    /// Set confidence to likely (0.8)
    pub fn likely(self: Builder) Builder {
        return self.withConfidence(0.8);
    }
    
    /// Set confidence to possible (0.5)
    pub fn possible(self: Builder) Builder {
        return self.withConfidence(0.5);
    }
    
    /// Set confidence to unlikely (0.2)
    pub fn unlikely(self: Builder) Builder {
        return self.withConfidence(0.2);
    }
    
    /// Build the fact (returns error if required fields are missing)
    pub fn build(self: Builder) !Fact {
        if (self.subject == null) return error.MissingSubject;
        if (self.predicate == null) return error.MissingPredicate;
        
        return Fact.init(
            self.id,
            self.subject.?,
            self.predicate.?,
            self.object,
            self.confidence,
        );
    }
    
    /// Build the fact with defaults for missing fields
    pub fn buildWithDefaults(self: Builder) Fact {
        return Fact.init(
            self.id,
            self.subject orelse 0,  // Empty packed span
            self.predicate orelse .is_token,
            self.object,
            self.confidence,
        );
    }
};

/// Helper functions for common fact patterns
pub const Patterns = struct {
    /// Create a token fact
    pub inline fn token(span: Span, kind: Predicate) Fact {
        return Builder.new()
            .withSpan(span)
            .withPredicate(kind)
            .certain()
            .buildWithDefaults();
    }
    
    /// Create a boundary fact
    pub inline fn boundary(span: Span) Fact {
        return Builder.new()
            .withSpan(span)
            .isBoundary()
            .certain()
            .buildWithDefaults();
    }
    
    /// Create a symbol definition fact
    pub inline fn symbolDef(span: Span, symbol_id: u32) Fact {
        return Builder.new()
            .withSpan(span)
            .definesSymbol()
            .withAtom(symbol_id)
            .certain()
            .buildWithDefaults();
    }
    
    /// Create a symbol reference fact
    pub inline fn symbolRef(span: Span, symbol_id: u32) Fact {
        return Builder.new()
            .withSpan(span)
            .referencesSymbol()
            .withAtom(symbol_id)
            .certain()
            .buildWithDefaults();
    }
    
    /// Create an error fact
    pub inline fn err(span: Span, error_code: i64) Fact {
        return Builder.new()
            .withSpan(span)
            .hasError()
            .withNumber(error_code)
            .certain()
            .buildWithDefaults();
    }
    
    /// Create a parent-child relationship
    pub inline fn parent(child_span: Span, parent_fact: FactId) Fact {
        return Builder.new()
            .withSpan(child_span)
            .withPredicate(.has_parent)
            .withFactRef(parent_fact)
            .certain()
            .buildWithDefaults();
    }
    
    /// Create an indentation level fact
    pub inline fn indent(span: Span, level: u64) Fact {
        return Builder.new()
            .withSpan(span)
            .withPredicate(.indent_level)
            .withUint(level)
            .certain()
            .buildWithDefaults();
    }
};