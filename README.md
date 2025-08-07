# zz

CLI utility toolkit with tree visualization and 2D game.

## Usage

```bash
./zz <command> [args...]
```

**Commands:**
- `tree [dir] [depth]` - Directory tree (filters common build/cache dirs)
- `yar` - 2D top-down shooter game (Raylib)
- `help` - Show commands

**Examples:**
```bash
./zz tree          # Current directory
./zz tree src/ 2   # src/ limited to 2 levels
./zz yar           # Play game (WASD+mouse)
```

## Building

```bash
zig build          # Builds to zig-out/bin/zz
./zz help          # Wrapper script auto-builds
```

The `zz` script automatically builds and runs the binary. Game requires Raylib static library in `src/raylib/lib/`.