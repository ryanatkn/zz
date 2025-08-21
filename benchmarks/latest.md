# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| ZON Lexer Small (1KB) | 700 | 338.8 | 484002 | +2.8% |
| ZON Lexer Medium (10KB) | 500 | 307.9 | 615868 | +1.1% |
| ZON Lexer Large (100KB) | 300 | 423.8 | 1412560 | -3.4% |
| ZON Lexer build.zig.zon | 900 | 328.7 | 365216 | -2.0% |
| ZON Lexer Config File | 900 | 328.9 | 365421 | -1.4% |
| Stream.next() throughput | 1757800 | 200.0 | 113 | +0.9% |
| RingBuffer push/pop | 1336700 | 200.0 | 149 | -1.3% |
| Map operator | 66200 | 200.1 | 3022 | -0.9% |
| Filter operator | 67600 | 200.0 | 2959 | -0.9% |
| FusedMap operator | 66400 | 200.1 | 3013 | -1.0% |
| Fact creation | 29073300 | 300.0 | 10 | +0.0% |
| FactStore append | 6200 | 303.0 | 48868 | -0.3% |
| Fact batch append (100) | 1000 | 300.2 | 300164 | +0.8% |
| Fact Builder DSL | 3431500 | 300.0 | 87 | +0.0% |
| Value type creation | 29018800 | 300.0 | 10 | +0.0% |
| PackedSpan pack/unpack | 9089300 | 200.0 | 22 | +0.0% |
| Span merge | 34672000 | 200.0 | 5 | +0.0% |
| Span intersect | 14223100 | 200.0 | 14 | +0.0% |
| SpanSet normalization | 4100 | 202.0 | 49276 | -2.3% |
| Span distance | 25667200 | 200.0 | 7 | +0.0% |
| SpanSet union | 2300 | 201.0 | 87387 | -2.0% |
| ArenaPool acquire/rotate | 8600 | 401.5 | 46688 | -1.9% |
| AtomTable interning | 3000 | 411.1 | 137027 | -3.2% |
| AtomTable lookup | 15873600 | 400.0 | 25 | +4.2% |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
