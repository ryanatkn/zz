# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 8100 | 400.5 | 49442 | -6.9% |
| Path Utilities | 30136100 | 400.0 | 13 | +0.0% |
| ArrayList Operations | 13000 | 640.2 | 49244 | -5.2% |
| HashMap Operations | 7000 | 691.8 | 98823 | -2.6% |
| Pattern Matching | 983700 | 400.0 | 406 | -1.2% |
| Text Line Processing | 4000 | 202.6 | 50653 | -3.6% |
| String Operations | 404900 | 200.0 | 493 | +0.0% |
| Character Predicates | 34343400 | 200.0 | 5 | +0.0% |
| Character Classification | 2104800 | 200.0 | 95 | -7.8% |
| JSON Text Analysis | 187900 | 300.0 | 1596 | -3.8% |
| ZON Text Analysis | 258400 | 300.1 | 1161 | +0.5% |
| Code Text Analysis | 87200 | 300.2 | 3442 | -0.2% |
| Traditional Full-Memory JSON (10KB) | 5300 | 401.3 | 75721 | -3.2% |
| Streaming TokenIterator JSON (10KB) | 700 | 415.6 | 593783 | -0.6% |
| Memory Usage Comparison (10KB) | 2400 | 410.2 | 170914 | +1.3% |
| Incremental Parser ZON (10KB) | 700 | 453.0 | 647136 | -8.5% |
| Direct Function Calls (Baseline) | 8000 | 404.2 | 50528 | +0.9% |
| Transform Pipeline (Small Chunks) | 7900 | 403.5 | 51079 | -2.8% |
| Transform Pipeline (Optimal Chunks) | 300 | 589.5 | 1964972 | +1.4% |
| ZON Lexer Small (1KB) | 700 | 332.4 | 474817 | -1.2% |
| ZON Lexer Medium (10KB) | 500 | 332.6 | 665170 | +9.2% |
| ZON Lexer Large (100KB) | 300 | 429.4 | 1431220 | -3.1% |
| ZON Lexer build.zig.zon | 900 | 331.5 | 368324 | +0.2% |
| ZON Lexer Config File | 900 | 328.8 | 365279 | -0.3% |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
