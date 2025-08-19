# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 8000 | 404.4 | 50545 | -4.9% |
| Path Utilities | 29182500 | 400.0 | 13 | +0.0% |
| ArrayList Operations | 13000 | 649.1 | 49933 | -3.9% |
| HashMap Operations | 6000 | 605.0 | 100825 | -0.6% |
| Pattern Matching | 955600 | 400.0 | 418 | +1.7% |
| Text Line Processing | 3900 | 201.5 | 51678 | -1.6% |
| String Operations | 403700 | 200.0 | 495 | +0.4% |
| Character Predicates | 36502800 | 200.0 | 5 | +0.0% |
| Character Classification | 1951900 | 200.0 | 102 | -1.0% |
| JSON Text Analysis | 180100 | 300.0 | 1665 | +0.4% |
| ZON Text Analysis | 257700 | 300.0 | 1164 | +0.8% |
| Code Text Analysis | 86000 | 300.0 | 3488 | +1.1% |
| Traditional Full-Memory JSON (10KB) | 5000 | 400.2 | 80034 | +2.4% |
| Streaming TokenIterator JSON (10KB) | 700 | 422.4 | 603498 | +1.0% |
| Memory Usage Comparison (10KB) | 2400 | 410.1 | 170892 | +1.3% |
| Incremental Parser ZON (10KB) | 600 | 437.6 | 729265 | +3.1% |
| Direct Function Calls (Baseline) | 7700 | 405.0 | 52597 | +5.0% |
| Transform Pipeline (Small Chunks) | 7200 | 400.3 | 55600 | +5.8% |
| Transform Pipeline (Optimal Chunks) | 200 | 401.1 | 2005401 | +3.5% |
| ZON Lexer Small (1KB) | 600 | 311.4 | 519060 | +8.0% |
| ZON Lexer Medium (10KB) | 500 | 318.4 | 636707 | +4.5% |
| ZON Lexer Large (100KB) | 300 | 437.5 | 1458476 | -1.3% |
| ZON Lexer build.zig.zon | 900 | 337.9 | 375389 | +2.1% |
| ZON Lexer Config File | 800 | 302.9 | 378586 | +3.3% |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
