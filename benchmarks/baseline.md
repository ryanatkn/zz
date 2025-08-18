# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (2s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 78169 | 4000.0 | 51171 | NEW |
| Path Utilities | 105609707 | 4000.0 | 37 | NEW |
| ArrayList Operations | 117609 | 6000.0 | 51016 | NEW |
| HashMap Operations | 59045 | 6000.0 | 101617 | NEW |
| Pattern Matching | 9133769 | 4000.0 | 437 | NEW |
| Text Line Processing | 39480 | 2000.0 | 50659 | NEW |
| String Operations | 3790820 | 2000.0 | 527 | NEW |
| Character Predicates | 59160554 | 2000.0 | 33 | NEW |
| Character Classification | 15309931 | 2000.0 | 130 | NEW |
| JSON Text Analysis | 1802649 | 3000.0 | 1664 | NEW |
| ZON Text Analysis | 2514134 | 3000.0 | 1193 | NEW |
| Code Text Analysis | 868705 | 3000.0 | 3453 | NEW |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
