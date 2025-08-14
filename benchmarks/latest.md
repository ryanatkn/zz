# Benchmark Results

**Date:** 2025-08-14 00:41:51  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 75520 | 4000 | 52979 | 51505 | +2.9% |
| String Pool | 11534509 | 2000 | 173 | 177 | -2.3% |
| Memory Pools | 115025 | 6000 | 52162 | 50957 | +2.4% |
| Glob Patterns | 102053676 | 4000 | 39 | 37 | +5.4% |
| Code Extraction | 20792 | 2000 | 96207 | 92152 | +4.4% |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
- **Code Extraction:** 4 extraction modes
