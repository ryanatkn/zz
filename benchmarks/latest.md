# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| ZON Lexer Small (1KB) | 1400 | 305.3 | 218072 | -53.5% |
| ZON Lexer Medium (10KB) | 700 | 320.9 | 458470 | -23.8% |
| ZON Lexer Large (100KB) | 300 | 388.0 | 1293465 | -6.7% |
| ZON Lexer build.zig.zon | 1400 | 305.2 | 218033 | -40.1% |
| ZON Lexer Config File | 1200 | 314.1 | 261748 | -27.8% |
| Stream.next() throughput | 1792000 | 200.0 | 111 | +0.9% |
| RingBuffer push/pop | 1331500 | 200.0 | 150 | +0.0% |
| Map operator | 63100 | 200.2 | 3172 | +5.9% |
| Filter operator | 65900 | 200.1 | 3036 | +2.9% |
| FusedMap operator | 66200 | 200.1 | 3022 | +0.3% |
| Fact creation | 29173100 | 300.0 | 10 | +11.1% |
| FactStore append | 6200 | 303.2 | 48901 | -0.9% |
| Fact batch append (100) | 1100 | 325.9 | 296313 | +0.9% |
| Fact Builder DSL | 3396700 | 300.0 | 88 | +1.1% |
| Value type creation | 30323300 | 300.0 | 9 | +0.0% |
| PackedSpan pack/unpack | 9257300 | 200.0 | 21 | +0.0% |
| Span merge | 33593800 | 200.0 | 5 | +0.0% |
| Span intersect | 14370900 | 200.0 | 13 | +0.0% |
| SpanSet normalization | 4000 | 200.6 | 50147 | +1.5% |
| Span distance | 23638400 | 200.0 | 8 | +14.3% |
| SpanSet union | 2300 | 201.7 | 87704 | +1.3% |
| ArenaPool acquire/rotate | 8300 | 401.0 | 48314 | +4.1% |
| AtomTable interning | 2900 | 410.7 | 141630 | +3.0% |
| AtomTable lookup | 16247800 | 400.0 | 24 | +4.3% |
| Simple query (SELECT predicate) | 700 | 331.8 | 473946 | NEW |
| Complex query (WHERE + ORDER BY + LIMIT) | 500 | 348.2 | 696420 | NEW |
| Query optimization overhead | 2000 | 312.3 | 156134 | NEW |
| Query planning overhead | 900 | 309.1 | 343405 | NEW |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
