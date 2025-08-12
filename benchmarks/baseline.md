# Benchmark Results

**Date:** 2025-08-12 18:46:36  
**Build:** Debug  
**Iterations:** 10000  

## Results

| Benchmark | Operations | Time (ms) | ns/op |
|-----------|------------|-----------|-------|
| Path Joining | 200000 | 10377 | 51887 |
| String Pool | 70000 | 10 | 145 |
| Memory Pools | 10000 | 501 | 50183 |
| Glob Patterns | 40000 | 0 | 23 |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
