# Benchmark Results

**Date:** 2025-08-13 05:18:25  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 79060 | 4000 | 50596 | 51765 | -2.3% |
| String Pool | 12012987 | 2000 | 166 | 178 | -6.7% |
| Memory Pools | 117304 | 6000 | 51149 | 52129 | -1.9% |
| Glob Patterns | 51743952 | 2000 | 38 | 38 | 0.0% |
| Code Extraction | 21196 | 2000 | 94370 | 95162 | -0.8% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
- **Code Extraction:** 4 extraction modes
