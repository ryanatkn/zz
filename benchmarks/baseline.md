# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 2000 | 104.3 | 52135 | NEW |
| Path Utilities | 7524000 | 100.0 | 13 | NEW |
| ArrayList Operations | 4000 | 196.7 | 49184 | NEW |
| HashMap Operations | 2000 | 193.3 | 96665 | NEW |
| Pattern Matching | 243000 | 100.2 | 412 | NEW |
| Text Line Processing | 1000 | 51.0 | 50978 | NEW |
| String Operations | 104000 | 50.2 | 482 | NEW |
| Character Predicates | 10461000 | 50.0 | 4 | NEW |
| Character Classification | 527000 | 50.1 | 95 | NEW |
| JSON Text Analysis | 47000 | 76.1 | 1618 | NEW |
| ZON Text Analysis | 66000 | 75.0 | 1136 | NEW |
| Code Text Analysis | 22000 | 75.2 | 3420 | NEW |
| Traditional Full-Memory JSON (10KB) | 2000 | 153.2 | 76583 | NEW |
| Streaming TokenIterator JSON (10KB) | 1000 | 597.5 | 597532 | NEW |
| Memory Usage Comparison (10KB) | 1000 | 168.5 | 168496 | NEW |
| Incremental Parser ZON (10KB) | 1000 | 732.2 | 732222 | NEW |
| Direct Function Calls (Baseline) | 2000 | 100.8 | 50402 | NEW |
| Transform Pipeline (Small Chunks) | 2000 | 104.1 | 52063 | NEW |
| Transform Pipeline (Optimal Chunks) | 1000 | 1967.3 | 1967270 | NEW |
| ZON Lexer Small (1KB) | 1000 | 477.7 | 477704 | NEW |
| ZON Lexer Medium (10KB) | 1000 | 615.6 | 615591 | NEW |
| ZON Lexer Large (100KB) | 1000 | 1419.9 | 1419890 | NEW |
| ZON Lexer build.zig.zon | 1000 | 369.6 | 369597 | NEW |
| ZON Lexer Config File | 1000 | 375.3 | 375307 | NEW |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
