# Config Module - Configuration System

Modular configuration system with ZON file parsing and pattern resolution.

## Components

- `shared.zig` - Core types and SharedConfig structure
- `zon.zig` - ZON file loading with filesystem abstraction
- `resolver.zig` - Pattern resolution with defaults and custom patterns

## Key Features

- Single source of truth in root `zz.zon`
- Pattern extension mode (defaults + custom)
- Safe path component matching
- Shared across tree and prompt modules