# Benchmark Results

**Date:** 2025-08-12 21:58:46  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 76560 | 4000 | 52257 | - | N/A |
| String Pool | 12671421 | 2000 | 157 | - | N/A |
| Memory Pools | 117084 | 6000 | 51245 | - | N/A |
| Glob Patterns | 56290848 | 2000 | 35 | - | N/A |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
