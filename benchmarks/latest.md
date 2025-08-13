# Benchmark Results

**Date:** 2025-08-13 13:28:18  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 78120 | 4000 | 51205 | 52391 | -2.3% |
| String Pool | 11973115 | 2000 | 167 | 176 | -5.1% |
| Memory Pools | 113243 | 6000 | 52983 | 53071 | -0.2% |
| Glob Patterns | 103284088 | 4000 | 38 | 38 | 0.0% |
| Code Extraction | 4732 | 2001 | 422975 | 413969 | +2.2% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
- **Code Extraction:** 4 extraction modes
