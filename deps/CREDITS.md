# Vendored Dependencies Credits

This document provides attribution for all vendored dependencies in the zz project.

## Table of Contents

- [Summary](#summary)
- [Core Libraries](#core-libraries)
- [Language Bindings](#language-bindings)
- [Language Grammars](#language-grammars)
- [Language Specifications](#language-specifications)
- [License Summary](#license-summary)

## Summary

The zz project vendors 9 dependencies to ensure reliable, reproducible builds without network access. All dependencies are MIT licensed and have been carefully selected for compatibility with our Zig 0.14.1 build system.

## Core Libraries

### tree-sitter

The foundational syntax tree parsing library that powers all language-aware features.

- **Version**: v0.25.0
- **Repository**: https://github.com/tree-sitter/tree-sitter
- **License**: MIT
- **Copyright**: © 2018-2024 Max Brunsfeld
- **Last Updated**: 2025-08-13 14:20:34 UTC
- **Purpose**: Core C library providing incremental parsing infrastructure
- **Key Contributors**: Max Brunsfeld and tree-sitter contributors

## Language Bindings

### zig-tree-sitter

Official Zig language bindings for the tree-sitter C API.

- **Version**: v0.25.0
- **Repository**: https://github.com/tree-sitter/zig-tree-sitter
- **License**: MIT
- **Copyright**: © 2024 tree-sitter contributors
- **Last Updated**: 2025-08-13 13:46:56 UTC
- **Purpose**: Idiomatic Zig interfaces to tree-sitter's C API
- **Note**: Provides the Zig module interface for using tree-sitter from Zig code

## Language Grammars

### tree-sitter-zig

Grammar for parsing Zig programming language source code.

- **Version**: main branch
- **Repository**: https://github.com/maxxnino/tree-sitter-zig
- **License**: MIT
- **Copyright**: © 2022 maxxnino
- **Last Updated**: 2025-08-13 13:47:03 UTC
- **Purpose**: Enables AST-based parsing of Zig source files
- **Note**: Based on the official Zig language specification

### tree-sitter-css

Grammar for parsing CSS stylesheets.

- **Version**: v0.23.0
- **Repository**: https://github.com/tree-sitter/tree-sitter-css
- **License**: MIT
- **Copyright**: © 2018 Max Brunsfeld
- **Last Updated**: 2025-08-13 16:26:17 UTC
- **Purpose**: CSS parsing for style extraction and analysis

### tree-sitter-html

Grammar for parsing HTML documents.

- **Version**: v0.23.0
- **Repository**: https://github.com/tree-sitter/tree-sitter-html
- **License**: MIT
- **Copyright**: © 2014 Max Brunsfeld
- **Last Updated**: 2025-08-13 16:26:43 UTC
- **Purpose**: HTML document structure parsing

### tree-sitter-json

Grammar for parsing JSON data.

- **Version**: v0.24.8
- **Repository**: https://github.com/tree-sitter/tree-sitter-json
- **License**: MIT
- **Copyright**: © 2014 Max Brunsfeld
- **Last Updated**: 2025-08-13 16:29:28 UTC
- **Purpose**: JSON structure validation and parsing

### tree-sitter-svelte

Grammar for parsing Svelte component files.

- **Version**: v1.0.2
- **Repository**: https://github.com/tree-sitter-grammars/tree-sitter-svelte
- **License**: MIT
- **Copyright**: © 2024 Amaan Qureshi <amaanq12@gmail.com>
- **Last Updated**: 2025-08-13 16:29:35 UTC
- **Purpose**: Multi-section Svelte component parsing (script/style/template)

### tree-sitter-typescript

Grammar for parsing TypeScript source code.

- **Version**: v0.7.0
- **Repository**: https://github.com/tree-sitter/tree-sitter-typescript
- **License**: MIT
- **Copyright**: © 2017 GitHub
- **Last Updated**: 2025-08-13 16:29:32 UTC
- **Purpose**: TypeScript language parsing (currently .ts files only)
- **Note**: Version compatibility issue noted for future resolution

## Language Specifications

### zig-spec

Official Zig language specification and grammar documentation.

- **Version**: main branch
- **Repository**: https://github.com/ziglang/zig-spec
- **License**: MIT
- **Copyright**: © 2018 Zig Programming Language
- **Last Updated**: 2025-08-13 13:47:17 UTC
- **Purpose**: Reference documentation for Zig language syntax and semantics
- **Note**: Documentation only, not compiled or linked

## License Summary

All vendored dependencies are licensed under the MIT License, ensuring compatibility with the zz project. Each dependency's LICENSE file is preserved in its respective directory.

## Build Configuration

The Zig build configuration for these dependencies has been adapted for the zz project with the following approach:

- Tree-sitter C libraries are compiled as static libraries
- Incompatible build files (using deprecated string literal names) have been removed
- Dependencies are managed via the `scripts/update-deps.sh` script
- Version tracking via `.version` files ensures reproducible builds

## Acknowledgments

We are grateful to all the maintainers and contributors of these projects:

- The tree-sitter project and community for creating a powerful, language-agnostic parsing framework
- Max Brunsfeld for founding tree-sitter and maintaining core grammars
- The Zig community for zig-spec and tooling support
- maxxnino for maintaining the tree-sitter-zig grammar
- Amaan Qureshi for the tree-sitter-svelte grammar
- GitHub for maintaining tree-sitter-typescript
- All contributors who have improved these projects over the years

## Update History

Dependencies last synchronized: 2025-08-13

For updating dependencies, see [deps/README.md](README.md#updating-dependencies).