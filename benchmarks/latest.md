# Benchmark Results

**Date:** 2025-08-12 18:50:39  
**Build:** Debug  
**Iterations:** 10000  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 200000 | 10377 | 51885 | 51887 | -0.0% |
| String Pool | 70000 | 13 | 189 | 145 | +30.3% |
| Memory Pools | 10000 | 508 | 50801 | 50183 | +1.2% |
| Glob Patterns | 40000 | 0 | 23 | 23 | 0.0% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
