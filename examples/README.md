# Example Files

This directory contains sample files in various languages to demonstrate zz's parsing capabilities.

## Files

- **app.ts** - TypeScript application with interfaces, types, and classes
- **styles.css** - Modern CSS with variables, grid layout, and media queries
- **index.html** - Semantic HTML5 document structure
- **config.json** - Nested JSON configuration file
- **component.svelte** - Svelte component with script, style, and template sections
- **runes.svelte.ts** - Svelte 5 reactive component using runes with TypeScript

## Running the Demo

From the project root:

```bash
./demo.sh
```

This will:
1. Show directory tree visualization of this examples directory
2. Parse each file type with appropriate extraction flags
3. Demonstrate glob pattern matching
4. Display performance benchmarks

## Extraction Examples

```bash
# Extract TypeScript interfaces and functions
zz prompt examples/app.ts --signatures --types

# Extract Svelte 5 runes and reactive patterns
zz prompt examples/runes.svelte.ts --signatures --types

# Extract CSS variables and selectors
zz prompt examples/styles.css --types

# Extract HTML structure
zz prompt examples/index.html --structure

# Parse all files with glob patterns
zz prompt 'examples/*.{ts,css,html,svelte}' --signatures
```