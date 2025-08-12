# Benchmark Results

**Date:** 2025-08-12 21:02:19  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 40080 | 2000 | 49902 | 52476 | -4.9% |
| String Pool | 12901280 | 2000 | 155 | 150 | +3.3% |
| Memory Pools | 39317 | 2000 | 50869 | 50651 | +0.4% |
| Glob Patterns | 59389264 | 2000 | 33 | 34 | -2.9% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
