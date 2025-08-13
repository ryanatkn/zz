# Benchmark Results

**Date:** 2025-08-13 05:21:27  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 78260 | 4000 | 51112 | - | N/A |
| String Pool | 11713163 | 2000 | 170 | - | N/A |
| Memory Pools | 117634 | 6000 | 51006 | - | N/A |
| Glob Patterns | 48940408 | 2000 | 40 | - | N/A |
| Code Extraction | 21356 | 2000 | 93666 | - | N/A |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
- **Code Extraction:** 4 extraction modes
