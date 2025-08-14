const std = @import("std");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const AstNode = @import("../ast.zig").AstNode;
const NodeVisitor = @import("../ast.zig").NodeVisitor;
const VisitResult = @import("../ast.zig").VisitResult;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // If no specific flags are set or full flag is set, return complete source
    if (flags.isDefault() or flags.full) {
        try result.appendSlice(source);
        return;
    }
    
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    var in_script = false;
    var in_style = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Track script and style sections
        if (std.mem.startsWith(u8, trimmed, "<script")) {
            in_script = true;
            if (flags.imports or flags.signatures) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "</script>")) {
            in_script = false;
            if (flags.imports or flags.signatures) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "<style")) {
            in_style = true;
            if (flags.types) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "</style>")) {
            in_style = false;
            if (flags.types) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            continue;
        }
        
        if (in_script) {
            // TypeScript/JavaScript extraction within script tags
            if (flags.signatures or flags.types) {
                if (std.mem.startsWith(u8, trimmed, "function ") or
                    std.mem.startsWith(u8, trimmed, "export ") or
                    std.mem.startsWith(u8, trimmed, "const ") or
                    std.mem.startsWith(u8, trimmed, "let ") or
                    std.mem.startsWith(u8, trimmed, "interface ") or
                    std.mem.startsWith(u8, trimmed, "type ") or
                    std.mem.indexOf(u8, trimmed, " => ") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.imports) {
                if (std.mem.startsWith(u8, trimmed, "import ")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        } else if (in_style) {
            // CSS extraction within style tags
            if (flags.types or flags.structure) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        } else {
            // HTML template extraction
            if (flags.structure) {
                if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "<!--")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.docs) {
                if (std.mem.startsWith(u8, trimmed, "<!--")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
    }
}

/// AST-based extraction using tree-sitter (when available)
pub fn walkNode(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var extraction_context = ExtractionContext{
        .allocator = allocator,
        .result = result,
        .flags = flags,
        .source = source,
        .current_section = .template, // Start in template section
    };
    
    // Svelte-specific extraction using visitor pattern
    var visitor = NodeVisitor.init(allocator, svelteExtractionVisitor, &extraction_context);
    try visitor.traverse(root, source);
}

const SvelteSection = enum {
    template,
    script,
    style,
};

const ExtractionContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    flags: ExtractionFlags,
    source: []const u8,
    current_section: SvelteSection,
};

/// Visitor function for Svelte extraction
fn svelteExtractionVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const extraction_ctx: *ExtractionContext = @ptrCast(@alignCast(ctx));
        
        // Update current section based on node type
        if (isScriptElement(node.node_type)) {
            extraction_ctx.current_section = .script;
        } else if (isStyleElement(node.node_type)) {
            extraction_ctx.current_section = .style;
        } else if (isTemplateElement(node.node_type)) {
            extraction_ctx.current_section = .template;
        }
        
        // Extract based on current section and flags
        switch (extraction_ctx.current_section) {
            .script => try extractScriptContent(extraction_ctx, node),
            .style => try extractStyleContent(extraction_ctx, node),
            .template => try extractTemplateContent(extraction_ctx, node),
        }
    }
    
    return VisitResult.continue_traversal;
}

/// Extract content from script sections
fn extractScriptContent(ctx: *ExtractionContext, node: *const AstNode) !void {
    if (ctx.flags.signatures or ctx.flags.types) {
        // Extract functions, variables, types from script
        if (isFunction(node.node_type) or isVariable(node.node_type) or isTypeDefinition(node.node_type)) {
            try ctx.result.appendSlice(node.text);
            try ctx.result.append('\n');
        }
    }
    
    if (ctx.flags.imports) {
        // Extract import statements
        if (isImport(node.node_type)) {
            try ctx.result.appendSlice(node.text);
            try ctx.result.append('\n');
        }
    }
}

/// Extract content from style sections
fn extractStyleContent(ctx: *ExtractionContext, node: *const AstNode) !void {
    if (ctx.flags.types or ctx.flags.structure) {
        // Extract CSS rules and selectors
        if (isCssRule(node.node_type) or isCssSelector(node.node_type)) {
            try ctx.result.appendSlice(node.text);
            try ctx.result.append('\n');
        }
    }
}

/// Extract content from template sections
fn extractTemplateContent(ctx: *ExtractionContext, node: *const AstNode) !void {
    if (ctx.flags.structure) {
        // Extract HTML elements and Svelte directives
        if (isElement(node.node_type) or isSvelteDirective(node.node_type)) {
            try ctx.result.appendSlice(node.text);
            try ctx.result.append('\n');
        }
    }
    
    if (ctx.flags.docs) {
        // Extract HTML comments
        if (isComment(node.node_type)) {
            try ctx.result.appendSlice(node.text);
            try ctx.result.append('\n');
        }
    }
}

/// Check if node represents a script element
pub fn isScriptElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "script_element") or
           std.mem.eql(u8, node_type, "raw_text") and 
           std.mem.indexOf(u8, node_type, "script") != null;
}

/// Check if node represents a style element
pub fn isStyleElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "style_element") or
           std.mem.eql(u8, node_type, "raw_text") and 
           std.mem.indexOf(u8, node_type, "style") != null;
}

/// Check if node represents a template element
pub fn isTemplateElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "element") or
           std.mem.eql(u8, node_type, "fragment") or
           std.mem.eql(u8, node_type, "text");
}

/// Check if node represents a function
pub fn isFunction(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "function_declaration") or
           std.mem.eql(u8, node_type, "function_expression") or
           std.mem.eql(u8, node_type, "arrow_function") or
           std.mem.eql(u8, node_type, "method_definition");
}

/// Check if node represents a variable declaration
pub fn isVariable(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "variable_declaration") or
           std.mem.eql(u8, node_type, "lexical_declaration") or
           std.mem.eql(u8, node_type, "variable_declarator");
}

/// Check if node represents a type definition
pub fn isTypeDefinition(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "interface_declaration") or
           std.mem.eql(u8, node_type, "type_alias_declaration") or
           std.mem.eql(u8, node_type, "enum_declaration");
}

/// Check if node represents an import statement
pub fn isImport(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "import_statement") or
           std.mem.eql(u8, node_type, "import_declaration");
}

/// Check if node represents a CSS rule
pub fn isCssRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "rule_set") or
           std.mem.eql(u8, node_type, "at_rule") or
           std.mem.eql(u8, node_type, "declaration");
}

/// Check if node represents a CSS selector
pub fn isCssSelector(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "selectors") or
           std.mem.eql(u8, node_type, "class_selector") or
           std.mem.eql(u8, node_type, "id_selector") or
           std.mem.eql(u8, node_type, "tag_name");
}

/// Check if node represents an HTML element
pub fn isElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "element") or
           std.mem.eql(u8, node_type, "start_tag") or
           std.mem.eql(u8, node_type, "end_tag") or
           std.mem.eql(u8, node_type, "self_closing_tag");
}

/// Check if node represents a Svelte directive
pub fn isSvelteDirective(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "directive") or
           std.mem.eql(u8, node_type, "if_block") or
           std.mem.eql(u8, node_type, "each_block") or
           std.mem.eql(u8, node_type, "await_block") or
           std.mem.eql(u8, node_type, "slot") or
           std.mem.eql(u8, node_type, "component") or
           std.mem.startsWith(u8, node_type, "svelte:");
}

/// Check if node represents a comment
pub fn isComment(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "comment");
}

/// Extract Svelte component props
pub fn extractProps(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, result: *std.ArrayList(u8)) !void {
    var context = PropsContext{
        .allocator = allocator,
        .result = result,
        .source = source,
        .in_script = false,
    };
    
    var visitor = NodeVisitor.init(allocator, extractPropsVisitor, &context);
    try visitor.traverse(root, source);
}

const PropsContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    source: []const u8,
    in_script: bool,
};

/// Visitor function for extracting Svelte component props
fn extractPropsVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const props_ctx: *PropsContext = @ptrCast(@alignCast(ctx));
        
        // Track script sections
        if (isScriptElement(node.node_type)) {
            props_ctx.in_script = true;
        }
        
        // Look for export declarations in script sections (Svelte props)
        if (props_ctx.in_script and 
            (std.mem.eql(u8, node.node_type, "export_statement") or
             (std.mem.eql(u8, node.node_type, "variable_declaration") and
              std.mem.startsWith(u8, node.text, "export")))) {
            try props_ctx.result.appendSlice(node.text);
            try props_ctx.result.append('\n');
        }
    }
    
    return VisitResult.continue_traversal;
}

/// Extract Svelte reactive statements ($:)
pub fn extractReactiveStatements(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, result: *std.ArrayList(u8)) !void {
    var context = ReactiveContext{
        .allocator = allocator,
        .result = result,
        .source = source,
    };
    
    var visitor = NodeVisitor.init(allocator, extractReactiveVisitor, &context);
    try visitor.traverse(root, source);
}

const ReactiveContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    source: []const u8,
};

/// Visitor function for extracting reactive statements
fn extractReactiveVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const reactive_ctx: *ReactiveContext = @ptrCast(@alignCast(ctx));
        
        // Look for reactive statements (lines starting with $:)
        if (std.mem.eql(u8, node.node_type, "labeled_statement") and
            std.mem.startsWith(u8, node.text, "$:")) {
            try reactive_ctx.result.appendSlice(node.text);
            try reactive_ctx.result.append('\n');
        }
    }
    
    return VisitResult.continue_traversal;
}

test "svelte script element detection" {
    const testing = std.testing;
    
    try testing.expect(isScriptElement("script_element"));
    try testing.expect(!isScriptElement("style_element"));
}

test "svelte style element detection" {
    const testing = std.testing;
    
    try testing.expect(isStyleElement("style_element"));
    try testing.expect(!isStyleElement("script_element"));
}

test "svelte function detection" {
    const testing = std.testing;
    
    try testing.expect(isFunction("function_declaration"));
    try testing.expect(isFunction("arrow_function"));
    try testing.expect(!isFunction("variable_declaration"));
}

test "svelte directive detection" {
    const testing = std.testing;
    
    try testing.expect(isSvelteDirective("if_block"));
    try testing.expect(isSvelteDirective("each_block"));
    try testing.expect(!isSvelteDirective("element"));
}

test "svelte variable detection" {
    const testing = std.testing;
    
    try testing.expect(isVariable("variable_declaration"));
    try testing.expect(isVariable("lexical_declaration"));
    try testing.expect(!isVariable("function_declaration"));
}