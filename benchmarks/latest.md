# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (2s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 79047 | 4000.0 | 50603 | -3.0% |
| Path Utilities | 105574014 | 4000.0 | 37 | -2.6% |
| ArrayList Operations | 120074 | 6000.0 | 49969 | -1.2% |
| HashMap Operations | 58118 | 6000.0 | 103238 | +0.1% |
| Pattern Matching | 9104335 | 4000.0 | 439 | -1.3% |
| Text Line Processing | 38931 | 2000.0 | 51373 | +0.3% |
| String Operations | 3756182 | 2000.0 | 532 | -3.3% |
| Character Predicates | 61237918 | 2000.0 | 32 | -5.9% |
| Character Classification | 16172379 | 2000.0 | 123 | -5.4% |
| JSON Text Analysis | 1827817 | 3000.0 | 1641 | -4.8% |
| ZON Text Analysis | 2547409 | 3000.0 | 1177 | -7.0% |
| Code Text Analysis | 875217 | 3000.0 | 3427 | -5.0% |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
