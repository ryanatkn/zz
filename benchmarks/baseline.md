# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 7600 | 403.8 | 53125 | NEW |
| Path Utilities | 29082200 | 400.0 | 13 | NEW |
| ArrayList Operations | 12000 | 623.3 | 51940 | NEW |
| HashMap Operations | 6000 | 608.8 | 101462 | NEW |
| Pattern Matching | 972200 | 400.0 | 411 | NEW |
| Text Line Processing | 3900 | 204.8 | 52519 | NEW |
| String Operations | 405300 | 200.0 | 493 | NEW |
| Character Predicates | 36613300 | 200.0 | 5 | NEW |
| Character Classification | 1940400 | 200.0 | 103 | NEW |
| JSON Text Analysis | 180900 | 300.2 | 1659 | NEW |
| ZON Text Analysis | 259700 | 300.1 | 1155 | NEW |
| Code Text Analysis | 87000 | 300.1 | 3449 | NEW |
| Traditional Full-Memory JSON (10KB) | 5200 | 406.6 | 78195 | NEW |
| Streaming TokenIterator JSON (10KB) | 700 | 418.1 | 597229 | NEW |
| Memory Usage Comparison (10KB) | 2400 | 404.8 | 168679 | NEW |
| Incremental Parser ZON (10KB) | 600 | 424.3 | 707203 | NEW |
| Direct Function Calls (Baseline) | 8000 | 400.7 | 50091 | NEW |
| Transform Pipeline (Small Chunks) | 7700 | 404.5 | 52528 | NEW |
| Transform Pipeline (Optimal Chunks) | 300 | 581.5 | 1938193 | NEW |
| ZON Lexer Small (1KB) | 700 | 336.6 | 480793 | NEW |
| ZON Lexer Medium (10KB) | 500 | 304.7 | 609307 | NEW |
| ZON Lexer Large (100KB) | 300 | 443.1 | 1476977 | NEW |
| ZON Lexer build.zig.zon | 900 | 330.8 | 367502 | NEW |
| ZON Lexer Config File | 900 | 329.9 | 366518 | NEW |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
