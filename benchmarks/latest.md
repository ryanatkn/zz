# Benchmark Results

**Date:** 2025-08-13 22:52:27  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 74600 | 4000 | 53631 | 51112 | +4.9% |
| String Pool | 11318188 | 2000 | 176 | 170 | +3.5% |
| Memory Pools | 110120 | 6000 | 54486 | 51006 | +6.8% |
| Glob Patterns | 101819604 | 4000 | 39 | 40 | -2.5% |
| Code Extraction | 20384 | 2000 | 98121 | 93666 | +4.8% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
- **Code Extraction:** 4 extraction modes
