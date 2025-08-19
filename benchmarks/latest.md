# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 3000 | 144.6 | 48208 | -10.2% |
| Path Utilities | 8255000 | 100.0 | 12 | +0.0% |
| ArrayList Operations | 4000 | 199.2 | 49808 | +2.7% |
| HashMap Operations | 2000 | 194.5 | 97243 | +2.7% |
| Pattern Matching | 245000 | 100.4 | 409 | +1.0% |
| Text Line Processing | 1000 | 51.9 | 51884 | +1.6% |
| String Operations | 101000 | 50.1 | 496 | +1.8% |
| Character Predicates | 10336000 | 50.0 | 4 | +0.0% |
| Character Classification | 509000 | 50.0 | 98 | +5.4% |
| JSON Text Analysis | 46000 | 76.3 | 1658 | +2.6% |
| ZON Text Analysis | 63000 | 75.7 | 1201 | +2.6% |
| Code Text Analysis | 22000 | 76.9 | 3496 | +0.6% |
| Traditional Full-Memory JSON (10KB) | 2000 | 153.8 | 76923 | +0.2% |
| Streaming TokenIterator JSON (10KB) | 1000 | 301.1 | 301056 | +2.5% |
| Memory Usage Comparison (10KB) | 1000 | 147.1 | 147062 | +1.8% |
| Incremental Parser ZON (10KB) | 1000 | 367.0 | 367003 | +3.0% |
| Direct Function Calls (Baseline) | 2000 | 102.0 | 51001 | +1.7% |
| Transform Pipeline (Small Chunks) | 2000 | 102.7 | 51356 | +1.6% |
| Transform Pipeline (Optimal Chunks) | 1000 | 573.2 | 573173 | +4.7% |
| ZON Lexer Small (1KB) | 1000 | 486.5 | 486455 | +2.3% |
| ZON Lexer Medium (10KB) | 1000 | 627.0 | 626985 | +2.9% |
| ZON Lexer Large (100KB) | 1000 | 1458.7 | 1458691 | +3.8% |
| ZON Lexer build.zig.zon | 1000 | 372.7 | 372670 | +2.0% |
| ZON Lexer Config File | 1000 | 368.5 | 368468 | +0.9% |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
