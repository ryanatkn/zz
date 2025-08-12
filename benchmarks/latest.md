# Benchmark Results

**Date:** 2025-08-12 20:14:32  
**Build:** Debug  
**Iterations:** 1000  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 4000 | 193 | 48324 | 53659 | -9.9% |
| String Pool | 1400000 | 225 | 160 | 141 | +13.5% |
| Memory Pools | 4000 | 210 | 52563 | 51602 | +1.9% |
| Glob Patterns | 8000000 | 209 | 26 | 26 | 0.0% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
