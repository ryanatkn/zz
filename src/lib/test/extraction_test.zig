const std = @import("std");
const testing = std.testing;
const Parser = @import("../parser.zig").Parser;
const Language = @import("../parser.zig").Language;
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;

// ============================================================================
// Zig Language Tests
// ============================================================================

test "Zig: extract function signatures" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .zig);
    defer parser.deinit();
    
    const source =
        \\pub fn main() void {
        \\    std.debug.print("Hello", .{});
        \\}
        \\
        \\fn helper() !void {
        \\    return error.NotImplemented;
        \\}
        \\
        \\const value = 42;
    ;
    
    const flags = ExtractionFlags{ .signatures = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain function signatures
    try testing.expect(std.mem.indexOf(u8, result, "pub fn main() void {") != null);
    try testing.expect(std.mem.indexOf(u8, result, "fn helper() !void {") != null);
    // Should NOT contain the const
    try testing.expect(std.mem.indexOf(u8, result, "const value") == null);
}

test "Zig: extract types and constants" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .zig);
    defer parser.deinit();
    
    const source =
        \\pub const MyStruct = struct {
        \\    field: u32,
        \\};
        \\
        \\const value = 42;
        \\var mutable: i32 = 0;
        \\
        \\fn notIncluded() void {}
    ;
    
    const flags = ExtractionFlags{ .types = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain types and constants
    try testing.expect(std.mem.indexOf(u8, result, "pub const MyStruct") != null);
    try testing.expect(std.mem.indexOf(u8, result, "const value = 42") != null);
    try testing.expect(std.mem.indexOf(u8, result, "var mutable") != null);
    // Should NOT contain functions
    try testing.expect(std.mem.indexOf(u8, result, "fn notIncluded") == null);
}

test "Zig: extract imports" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .zig);
    defer parser.deinit();
    
    const source =
        \\const std = @import("std");
        \\const testing = std.testing;
        \\const myModule = @import("my_module.zig");
        \\
        \\fn main() void {
        \\    const local = @import("local.zig");
        \\}
    ;
    
    const flags = ExtractionFlags{ .imports = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain all imports
    try testing.expect(std.mem.indexOf(u8, result, "@import(\"std\")") != null);
    try testing.expect(std.mem.indexOf(u8, result, "@import(\"my_module.zig\")") != null);
    try testing.expect(std.mem.indexOf(u8, result, "@import(\"local.zig\")") != null);
}

// ============================================================================
// CSS Language Tests
// ============================================================================

test "CSS: extract with types flag" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .css);
    defer parser.deinit();
    
    const source =
        \\:root {
        \\    --primary-color: #007bff;
        \\    --spacing: 1rem;
        \\}
        \\
        \\.container {
        \\    max-width: 1200px;
        \\    margin: 0 auto;
        \\}
        \\
        \\@media (max-width: 768px) {
        \\    .container {
        \\        padding: 0 1rem;
        \\    }
        \\}
    ;
    
    const flags = ExtractionFlags{ .types = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // With types flag, CSS returns everything (all structure)
    try testing.expect(std.mem.indexOf(u8, result, ":root") != null);
    try testing.expect(std.mem.indexOf(u8, result, "--primary-color") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".container") != null);
    try testing.expect(std.mem.indexOf(u8, result, "@media") != null);
}

test "CSS: extract selectors only with signatures" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .css);
    defer parser.deinit();
    
    const source =
        \\.btn {
        \\    background: blue;
        \\}
        \\
        \\#header {
        \\    height: 60px;
        \\}
        \\
        \\/* Comment should not appear */
        \\body {
        \\    margin: 0;
        \\}
    ;
    
    const flags = ExtractionFlags{ .signatures = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain selectors
    try testing.expect(std.mem.indexOf(u8, result, ".btn") != null);
    try testing.expect(std.mem.indexOf(u8, result, "#header") != null);
    try testing.expect(std.mem.indexOf(u8, result, "body {") != null);
}

test "CSS: extract imports" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .css);
    defer parser.deinit();
    
    const source =
        \\@import url('fonts.css');
        \\@import "variables.css";
        \\@use 'sass:math';
        \\
        \\body {
        \\    font-family: sans-serif;
        \\}
    ;
    
    const flags = ExtractionFlags{ .imports = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain imports
    try testing.expect(std.mem.indexOf(u8, result, "@import url('fonts.css')") != null);
    try testing.expect(std.mem.indexOf(u8, result, "@import \"variables.css\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "@use 'sass:math'") != null);
    // Should NOT contain body
    try testing.expect(std.mem.indexOf(u8, result, "body") == null);
}

// ============================================================================
// HTML Language Tests
// ============================================================================

test "HTML: extract structure" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .html);
    defer parser.deinit();
    
    const source =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <title>Test Page</title>
        \\</head>
        \\<body>
        \\    <h1>Hello World</h1>
        \\    <!-- Comment -->
        \\    <p>Content here</p>
        \\</body>
        \\</html>
    ;
    
    const flags = ExtractionFlags{ .structure = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain all HTML tags
    try testing.expect(std.mem.indexOf(u8, result, "<!DOCTYPE html>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<html lang=\"en\">") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<head>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<title>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<body>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<h1>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<p>") != null);
}

test "HTML: extract script functions with signatures" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .html);
    defer parser.deinit();
    
    const source =
        \\<html>
        \\<head>
        \\    <script>
        \\        function init() {
        \\            console.log('Starting');
        \\        }
        \\    </script>
        \\</head>
        \\<body onclick="handleClick()">
        \\    <button onclick="doSomething()">Click</button>
        \\</body>
        \\</html>
    ;
    
    const flags = ExtractionFlags{ .signatures = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain script tags and functions
    try testing.expect(std.mem.indexOf(u8, result, "<script>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "function init()") != null);
    try testing.expect(std.mem.indexOf(u8, result, "onclick=\"handleClick()\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "onclick=\"doSomething()\"") != null);
}

test "HTML: extract comments with docs flag" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .html);
    defer parser.deinit();
    
    const source =
        \\<html>
        \\<!-- Header Section -->
        \\<header>
        \\    <!-- Navigation Menu -->
        \\    <nav>Menu</nav>
        \\</header>
        \\<!-- Main Content -->
        \\<main>Content</main>
        \\</html>
    ;
    
    const flags = ExtractionFlags{ .docs = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain comments
    try testing.expect(std.mem.indexOf(u8, result, "<!-- Header Section -->") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<!-- Navigation Menu -->") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<!-- Main Content -->") != null);
    // Should NOT contain regular tags
    try testing.expect(std.mem.indexOf(u8, result, "<header>") == null);
    try testing.expect(std.mem.indexOf(u8, result, "<nav>") == null);
}

// ============================================================================
// JSON Language Tests
// ============================================================================

test "JSON: extract structure" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .json);
    defer parser.deinit();
    
    const source =
        \\{
        \\  "name": "test-app",
        \\  "version": "1.0.0",
        \\  "config": {
        \\    "port": 3000,
        \\    "debug": true
        \\  },
        \\  "dependencies": [
        \\    "express",
        \\    "lodash"
        \\  ]
        \\}
    ;
    
    const flags = ExtractionFlags{ .structure = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // With structure flag, JSON returns everything
    try testing.expect(std.mem.indexOf(u8, result, "\"name\": \"test-app\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"version\": \"1.0.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"config\": {") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"port\": 3000") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"dependencies\": [") != null);
}

test "JSON: extract keys only with signatures" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .json);
    defer parser.deinit();
    
    const source =
        \\{
        \\  "name": "app",
        \\  "nested": {
        \\    "key1": "value1",
        \\    "key2": 123
        \\  }
        \\}
    ;
    
    const flags = ExtractionFlags{ .signatures = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain lines with keys
    try testing.expect(std.mem.indexOf(u8, result, "\"name\":") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"key1\":") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"key2\":") != null);
}

// ============================================================================
// TypeScript Language Tests
// ============================================================================

test "TypeScript: extract interfaces and types" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .typescript);
    defer parser.deinit();
    
    const source =
        \\interface User {
        \\    id: number;
        \\    name: string;
        \\}
        \\
        \\type Role = 'admin' | 'user';
        \\
        \\export interface ApiResponse {
        \\    data: any;
        \\    status: number;
        \\}
        \\
        \\function notIncluded() {
        \\    return 42;
        \\}
    ;
    
    const flags = ExtractionFlags{ .types = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain interfaces and types
    try testing.expect(std.mem.indexOf(u8, result, "interface User") != null);
    try testing.expect(std.mem.indexOf(u8, result, "id: number") != null);
    try testing.expect(std.mem.indexOf(u8, result, "type Role") != null);
    try testing.expect(std.mem.indexOf(u8, result, "export interface ApiResponse") != null);
    // Should NOT contain function when only types requested
    try testing.expect(std.mem.indexOf(u8, result, "function notIncluded") == null);
}

test "TypeScript: extract function signatures" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .typescript);
    defer parser.deinit();
    
    const source =
        \\function regularFunction(x: number): string {
        \\    return x.toString();
        \\}
        \\
        \\export async function asyncFunc(): Promise<void> {
        \\    await something();
        \\}
        \\
        \\const arrowFunc = (a: string, b: number) => {
        \\    return a + b;
        \\};
        \\
        \\export const shortArrow = () => console.log('hi');
        \\
        \\interface NotIncluded {
        \\    field: string;
        \\}
    ;
    
    const flags = ExtractionFlags{ .signatures = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain function signatures
    try testing.expect(std.mem.indexOf(u8, result, "function regularFunction") != null);
    try testing.expect(std.mem.indexOf(u8, result, "export async function asyncFunc") != null);
    try testing.expect(std.mem.indexOf(u8, result, "const arrowFunc") != null);
    try testing.expect(std.mem.indexOf(u8, result, "=>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "export const shortArrow") != null);
    // Should NOT contain interface
    try testing.expect(std.mem.indexOf(u8, result, "interface NotIncluded") == null);
}

test "TypeScript: extract imports" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .typescript);
    defer parser.deinit();
    
    const source =
        \\import { Component } from 'react';
        \\import * as fs from 'fs';
        \\import defaultExport from 'module';
        \\export { something } from './local';
        \\
        \\const notAnImport = 'import';
        \\
        \\export const value = 42;
    ;
    
    const flags = ExtractionFlags{ .imports = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain imports and exports
    try testing.expect(std.mem.indexOf(u8, result, "import { Component }") != null);
    try testing.expect(std.mem.indexOf(u8, result, "import * as fs") != null);
    try testing.expect(std.mem.indexOf(u8, result, "import defaultExport") != null);
    try testing.expect(std.mem.indexOf(u8, result, "export { something }") != null);
    try testing.expect(std.mem.indexOf(u8, result, "export const value") != null);
    // Should NOT contain the fake import
    try testing.expect(std.mem.indexOf(u8, result, "const notAnImport") == null);
}

// ============================================================================
// Svelte Language Tests
// ============================================================================

test "Svelte: extract script section with signatures" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .svelte);
    defer parser.deinit();
    
    const source =
        \\<script lang="ts">
        \\  import { onMount } from 'svelte';
        \\  
        \\  export let name: string;
        \\  let count = 0;
        \\  
        \\  function increment() {
        \\    count += 1;
        \\  }
        \\  
        \\  const doubled = () => count * 2;
        \\</script>
        \\
        \\<style>
        \\  .container { padding: 1rem; }
        \\</style>
        \\
        \\<div>Not included</div>
    ;
    
    const flags = ExtractionFlags{ .signatures = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain script tags and functions
    try testing.expect(std.mem.indexOf(u8, result, "<script") != null);
    try testing.expect(std.mem.indexOf(u8, result, "</script>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "export let name") != null);
    try testing.expect(std.mem.indexOf(u8, result, "function increment") != null);
    try testing.expect(std.mem.indexOf(u8, result, "const doubled") != null);
    // Should NOT contain style or template
    try testing.expect(std.mem.indexOf(u8, result, ".container") == null);
    try testing.expect(std.mem.indexOf(u8, result, "<div>") == null);
}

test "Svelte: extract style section with types" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .svelte);
    defer parser.deinit();
    
    const source =
        \\<script>
        \\  let value = 0;
        \\</script>
        \\
        \\<style>
        \\  :global(body) {
        \\    margin: 0;
        \\  }
        \\  
        \\  .card {
        \\    background: white;
        \\    border-radius: 8px;
        \\  }
        \\  
        \\  @media (max-width: 600px) {
        \\    .card { padding: 0.5rem; }
        \\  }
        \\</style>
        \\
        \\<div class="card">Content</div>
    ;
    
    const flags = ExtractionFlags{ .types = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain style section
    try testing.expect(std.mem.indexOf(u8, result, "<style>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "</style>") != null);
    try testing.expect(std.mem.indexOf(u8, result, ":global(body)") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".card") != null);
    try testing.expect(std.mem.indexOf(u8, result, "@media") != null);
    // Should also contain script types (let declarations)
    try testing.expect(std.mem.indexOf(u8, result, "let value") != null);
}

test "Svelte: extract template structure" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .svelte);
    defer parser.deinit();
    
    const source =
        \\<script>
        \\  export let items = [];
        \\</script>
        \\
        \\<main>
        \\  <h1>Title</h1>
        \\  {#if items.length > 0}
        \\    <ul>
        \\      {#each items as item}
        \\        <li>{item}</li>
        \\      {/each}
        \\    </ul>
        \\  {/if}
        \\  <button on:click={handleClick}>Click me</button>
        \\</main>
    ;
    
    const flags = ExtractionFlags{ .structure = true };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain HTML template structure
    try testing.expect(std.mem.indexOf(u8, result, "<main>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<h1>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<ul>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<li>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "<button") != null);
}

// ============================================================================
// Edge Cases and Combined Flags
// ============================================================================

test "Multiple flags combined" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .typescript);
    defer parser.deinit();
    
    const source =
        \\import { lib } from 'library';
        \\
        \\interface Config {
        \\    port: number;
        \\}
        \\
        \\function setup(config: Config) {
        \\    return config.port;
        \\}
    ;
    
    // Combine signatures, types, and imports
    const flags = ExtractionFlags{ 
        .signatures = true,
        .types = true,
        .imports = true,
    };
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should contain all requested elements
    try testing.expect(std.mem.indexOf(u8, result, "import { lib }") != null);
    try testing.expect(std.mem.indexOf(u8, result, "interface Config") != null);
    try testing.expect(std.mem.indexOf(u8, result, "function setup") != null);
}

test "Empty source handling" {
    const allocator = testing.allocator;
    
    const languages = [_]Language{ .zig, .css, .html, .json, .typescript, .svelte };
    
    for (languages) |lang| {
        var parser = try Parser.init(allocator, lang);
        defer parser.deinit();
        
        const flags = ExtractionFlags{ .signatures = true };
        const result = try parser.extract("", flags);
        defer allocator.free(result);
        
        // Should handle empty source gracefully
        try testing.expectEqual(@as(usize, 0), result.len);
    }
}

test "Default flags behavior (full extraction)" {
    const allocator = testing.allocator;
    var parser = try Parser.init(allocator, .css);
    defer parser.deinit();
    
    const source = ".class { color: red; }";
    
    // No flags set, should default to full
    var flags = ExtractionFlags{};
    flags.setDefault();
    
    const result = try parser.extract(source, flags);
    defer allocator.free(result);
    
    // Should return full source
    try testing.expectEqualStrings(source, result);
}