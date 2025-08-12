# Benchmark Results

**Date:** 2025-08-12 20:07:56  
**Build:** Debug  
**Iterations:** 1000  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 4000 | 214 | 53659 | - | N/A |
| String Pool | 1400000 | 197 | 141 | - | N/A |
| Memory Pools | 4000 | 206 | 51602 | - | N/A |
| Glob Patterns | 8000000 | 208 | 26 | - | N/A |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
