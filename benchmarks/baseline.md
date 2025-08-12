# Benchmark Results

**Date:** 2025-08-12 21:00:11  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 38120 | 2000 | 52476 | - | N/A |
| String Pool | 13281240 | 2000 | 150 | - | N/A |
| Memory Pools | 39486 | 2000 | 50651 | - | N/A |
| Glob Patterns | 58444380 | 2000 | 34 | - | N/A |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
