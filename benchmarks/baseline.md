# Benchmark Results

**Date:** 2025-08-14 00:40:42  
**Build:** Debug  
**Duration per benchmark:** 2.00 s  

## Results

| Benchmark | Operations | Time (ms) | ns/op | Baseline | Change |
|-----------|------------|-----------|-------|----------|--------|
| Path Joining | 77680 | 4000 | 51505 | - | N/A |
| String Pool | 11236050 | 2000 | 177 | - | N/A |
| Memory Pools | 117746 | 6000 | 50957 | - | N/A |
| Glob Patterns | 107515572 | 4000 | 37 | - | N/A |
| Code Extraction | 21704 | 2000 | 92152 | - | N/A |

## Notes

- **String Pool:** Cache efficiency: 100.0%
- **Glob Patterns:** Fast path hit ratio: 75.0%
- **Code Extraction:** 4 extraction modes
