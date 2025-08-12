# Benchmark Results

**Date:** 2025-08-12 22:40:54  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 78920 | 4000 | 50696 | 51799 | -2.1% |
| String Pool | 12894014 | 2000 | 155 | 154 | +0.6% |
| Memory Pools | 118496 | 6000 | 50635 | 50978 | -0.7% |
| Glob Patterns | 57261176 | 2000 | 34 | 35 | -2.9% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
