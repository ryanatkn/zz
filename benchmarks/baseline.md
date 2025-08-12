# Benchmark Results

**Date:** 2025-08-12 22:40:40  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 77240 | 4001 | 51799 | - | N/A |
| String Pool | 12906649 | 2000 | 154 | - | N/A |
| Memory Pools | 117697 | 6000 | 50978 | - | N/A |
| Glob Patterns | 57103064 | 2000 | 35 | - | N/A |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
