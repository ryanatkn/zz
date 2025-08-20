# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 8000 | 403.5 | 50443 | NEW |
| Path Utilities | 30526400 | 400.0 | 13 | NEW |
| ArrayList Operations | 12000 | 621.8 | 51819 | NEW |
| HashMap Operations | 6000 | 602.3 | 100391 | NEW |
| Pattern Matching | 967700 | 400.0 | 413 | NEW |
| Text Line Processing | 3900 | 201.3 | 51618 | NEW |
| String Operations | 408000 | 200.0 | 490 | NEW |
| Character Predicates | 34270100 | 200.0 | 5 | NEW |
| Character Classification | 2086300 | 200.0 | 95 | NEW |
| JSON Text Analysis | 182500 | 300.0 | 1644 | NEW |
| ZON Text Analysis | 256600 | 300.1 | 1169 | NEW |
| Code Text Analysis | 87100 | 300.1 | 3445 | NEW |
| Traditional Full-Memory JSON (10KB) | 5300 | 403.1 | 76047 | NEW |
| Streaming TokenIterator JSON (10KB) | 700 | 424.4 | 606247 | NEW |
| Memory Usage Comparison (10KB) | 2400 | 411.9 | 171615 | NEW |
| Incremental Parser ZON (10KB) | 700 | 459.9 | 657005 | NEW |
| Direct Function Calls (Baseline) | 7900 | 404.9 | 51256 | NEW |
| Transform Pipeline (Small Chunks) | 7800 | 401.9 | 51520 | NEW |
| Transform Pipeline (Optimal Chunks) | 200 | 406.1 | 2030374 | NEW |
| ZON Lexer Small (1KB) | 700 | 337.7 | 482434 | NEW |
| ZON Lexer Medium (10KB) | 500 | 311.8 | 623644 | NEW |
| ZON Lexer Large (100KB) | 300 | 423.4 | 1411417 | NEW |
| ZON Lexer build.zig.zon | 900 | 332.0 | 368929 | NEW |
| ZON Lexer Config File | 900 | 327.7 | 364087 | NEW |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
