# Benchmark Results

**Date:** 2025-08-12 20:32:29  
**Build:** Debug  
**Iterations:** 1000  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 4000 | 212 | 53194 | - | N/A |
| String Pool | 1400000 | 200 | 143 | - | N/A |
| Memory Pools | 4000 | 216 | 54068 | - | N/A |
| Glob Patterns | 8000000 | 222 | 27 | - | N/A |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
