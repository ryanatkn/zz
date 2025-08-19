# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 2000 | 102.1 | 51054 | NEW |
| Path Utilities | 8451000 | 100.0 | 11 | NEW |
| ArrayList Operations | 4000 | 193.3 | 48316 | NEW |
| HashMap Operations | 2000 | 189.3 | 94669 | NEW |
| Pattern Matching | 248000 | 100.2 | 403 | NEW |
| Text Line Processing | 1000 | 50.9 | 50930 | NEW |
| String Operations | 102000 | 50.3 | 492 | NEW |
| Character Predicates | 10443000 | 50.0 | 4 | NEW |
| Character Classification | 496000 | 50.0 | 100 | NEW |
| JSON Text Analysis | 46000 | 76.3 | 1658 | NEW |
| ZON Text Analysis | 64000 | 76.0 | 1186 | NEW |
| Code Text Analysis | 22000 | 75.9 | 3449 | NEW |
| Traditional Full-Memory JSON (10KB) | 2000 | 153.0 | 76499 | NEW |
| Streaming TokenIterator JSON (10KB) | 1000 | 297.3 | 297330 | NEW |
| Memory Usage Comparison (10KB) | 1000 | 141.8 | 141785 | NEW |
| Incremental Parser ZON (10KB) | 1000 | 360.5 | 360537 | NEW |
| Direct Function Calls (Baseline) | 2000 | 101.2 | 50620 | NEW |
| Transform Pipeline (Small Chunks) | 2000 | 101.9 | 50960 | NEW |
| Transform Pipeline (Optimal Chunks) | 1000 | 560.1 | 560107 | NEW |
| ZON Lexer Small (1KB) | 1000 | 477.1 | 477109 | NEW |
| ZON Lexer Medium (10KB) | 1000 | 634.3 | 634264 | NEW |
| ZON Lexer Large (100KB) | 1000 | 1421.9 | 1421871 | NEW |
| ZON Lexer build.zig.zon | 1000 | 366.2 | 366167 | NEW |
| ZON Lexer Config File | 1000 | 366.1 | 366078 | NEW |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
