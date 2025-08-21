# Transform Module - Pipeline Infrastructure

## Purpose
Transform pipelines for progressive data enrichment. Supports token → fact, AST → fact, and other transformations.

## Architecture
- **Pipeline Composition** - Chain transforms like Unix pipes
- **Progressive Enrichment** - Add information in stages
- **Zero-Allocation Core** - Stream transforms without allocation
- **Optional Semantics** - Rich transforms only when needed

## Files
- `mod.zig` - Pure re-exports only
- `pipeline.zig` - Pipeline infrastructure
- `format.zig` - Formatting transforms
- `extract.zig` - Extraction transforms
- `optimize.zig` - Optimization transforms

## Usage
```zig
// Create pipeline
var pipeline = Pipeline.init(allocator);
defer pipeline.deinit();

// Add transforms
try pipeline.add(TokenToFact{});
try pipeline.add(FormatTransform{});

// Execute pipeline
const result = try pipeline.execute(tokens);
```

## Design Principles
- Transforms are composable functions
- Each stage is optional
- Streaming preferred over batch
- Memory efficiency is critical