# Benchmark Results

**Date:** 2025-08-12 21:59:55  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 78220 | 4000 | 51147 | 52257 | -2.1% |
| String Pool | 12507565 | 2000 | 159 | 157 | +1.3% |
| Memory Pools | 117351 | 6000 | 51128 | 51245 | -0.2% |
| Glob Patterns | 57289528 | 2000 | 34 | 35 | -2.9% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
