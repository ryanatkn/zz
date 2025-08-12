# Benchmark Results

**Date:** 2025-08-12 20:32:38  
**Build:** Debug  
**Iterations:** 1000  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 4000 | 189 | 47364 | 53194 | -11.0% |
| String Pool | 1400000 | 200 | 142 | 143 | -0.7% |
| Memory Pools | 4000 | 206 | 51645 | 54068 | -4.5% |
| Glob Patterns | 8000000 | 209 | 26 | 27 | -3.7% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
