# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (2s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| ZON Lexer Small (1KB) | 7000 | 3279.8 | 468536 | NEW |
| ZON Lexer Medium (10KB) | 5000 | 3007.9 | 601584 | NEW |
| ZON Lexer Large (100KB) | 3000 | 4160.2 | 1386739 | NEW |
| ZON Lexer build.zig.zon | 9000 | 3273.9 | 363769 | NEW |
| ZON Lexer Config File | 9000 | 3263.7 | 362635 | NEW |
| Stream.next() throughput | 18048000 | 2000.0 | 110 | NEW |
| RingBuffer push/pop | 13317000 | 2000.1 | 150 | NEW |
| Map operator | 668000 | 2000.0 | 2994 | NEW |
| Filter operator | 678000 | 2001.1 | 2951 | NEW |
| FusedMap operator | 664000 | 2000.9 | 3013 | NEW |
| Fact creation | 305385000 | 3000.0 | 9 | NEW |
| FactStore append | 61000 | 3009.7 | 49339 | NEW |
| Fact batch append (100) | 11000 | 3229.5 | 293591 | NEW |
| Fact Builder DSL | 34443000 | 3000.1 | 87 | NEW |
| Value type creation | 304919000 | 3000.0 | 9 | NEW |
| PackedSpan pack/unpack | 92432000 | 2000.0 | 21 | NEW |
| Span merge | 367167000 | 2000.0 | 5 | NEW |
| Span intersect | 144958000 | 2000.0 | 13 | NEW |
| SpanSet normalization | 41000 | 2026.0 | 49415 | NEW |
| Span distance | 275557000 | 2000.0 | 7 | NEW |
| SpanSet union | 24000 | 2077.3 | 86554 | NEW |
| ArenaPool acquire/rotate | 87000 | 4039.3 | 46428 | NEW |
| AtomTable interning | 30000 | 4125.0 | 137499 | NEW |
| AtomTable lookup | 169619000 | 4000.0 | 23 | NEW |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
