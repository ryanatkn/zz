# Benchmark Results

**Date:** 2025-08-13 19:14:58  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 77240 | 4000 | 51789 | 51112 | +1.3% |
| String Pool | 11459133 | 2000 | 174 | 170 | +2.4% |
| Memory Pools | 116353 | 6000 | 51567 | 51006 | +1.1% |
| Glob Patterns | 100836476 | 4000 | 39 | 40 | -2.5% |
| Code Extraction | 20804 | 2000 | 96150 | 93666 | +2.7% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
- **Code Extraction:** 4 extraction modes
