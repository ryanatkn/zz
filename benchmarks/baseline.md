# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (0s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| ZON Lexer Small (1KB) | 700 | 329.6 | 470862 | NEW |
| ZON Lexer Medium (10KB) | 500 | 304.7 | 609417 | NEW |
| ZON Lexer Large (100KB) | 300 | 438.5 | 1461591 | NEW |
| ZON Lexer build.zig.zon | 900 | 335.4 | 372643 | NEW |
| ZON Lexer Config File | 900 | 333.7 | 370723 | NEW |
| Stream.next() throughput | 1784400 | 200.0 | 112 | NEW |
| RingBuffer push/pop | 1319200 | 200.0 | 151 | NEW |
| Map operator | 65600 | 200.0 | 3049 | NEW |
| Filter operator | 67000 | 200.0 | 2985 | NEW |
| FusedMap operator | 65800 | 200.3 | 3043 | NEW |
| Fact creation | 28861700 | 300.0 | 10 | NEW |
| FactStore append | 6200 | 303.8 | 49006 | NEW |
| Fact batch append (100) | 1100 | 327.5 | 297715 | NEW |
| Fact Builder DSL | 3409300 | 300.0 | 87 | NEW |
| Value type creation | 29061600 | 300.0 | 10 | NEW |
| PackedSpan pack/unpack | 9063700 | 200.0 | 22 | NEW |
| Span merge | 33948100 | 200.0 | 5 | NEW |
| Span intersect | 13841800 | 200.0 | 14 | NEW |
| SpanSet normalization | 4000 | 201.8 | 50452 | NEW |
| Span distance | 25377000 | 200.0 | 7 | NEW |
| SpanSet union | 2300 | 205.1 | 89166 | NEW |
| ArenaPool acquire/rotate | 8500 | 404.5 | 47583 | NEW |
| AtomTable interning | 2900 | 410.5 | 141564 | NEW |
| AtomTable lookup | 16243400 | 400.0 | 24 | NEW |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
