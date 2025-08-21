# Benchmark Results

Date: 2025-01-01 00:00:00
Build: Debug
Iterations: Time-based (2s duration)

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| ZON Lexer Small (1KB) | 7000 | 3283.0 | 469004 | +0.1% |
| ZON Lexer Medium (10KB) | 5000 | 3047.1 | 609411 | +1.3% |
| ZON Lexer Large (100KB) | 3000 | 4223.7 | 1407915 | +1.5% |
| ZON Lexer build.zig.zon | 9000 | 3245.9 | 360650 | -0.9% |
| ZON Lexer Config File | 9000 | 3263.9 | 362653 | +0.0% |
| Stream.next() throughput | 18091000 | 2000.0 | 110 | +0.0% |
| RingBuffer push/pop | 13142000 | 2000.1 | 152 | +1.3% |
| Map operator | 662000 | 2001.7 | 3023 | +1.0% |
| Filter operator | 677000 | 2001.4 | 2956 | +0.2% |
| FusedMap operator | 650000 | 2000.7 | 3077 | +2.1% |
| Fact creation | 304072000 | 3000.0 | 9 | +0.0% |
| FactStore append | 61000 | 3033.8 | 49735 | +0.8% |
| Fact batch append (100) | 11000 | 3254.8 | 295891 | +0.8% |
| Fact Builder DSL | 34170000 | 3000.1 | 87 | +0.0% |
| Value type creation | 296168000 | 3000.0 | 10 | +11.1% |
| PackedSpan pack/unpack | 93851000 | 2000.0 | 21 | +0.0% |
| Span merge | 373615000 | 2000.0 | 5 | +0.0% |
| Span intersect | 147450000 | 2000.0 | 13 | +0.0% |
| SpanSet normalization | 41000 | 2020.4 | 49279 | -0.3% |
| Span distance | 272010000 | 2000.0 | 7 | +0.0% |
| SpanSet union | 24000 | 2081.3 | 86720 | +0.2% |
| ArenaPool acquire/rotate | 84000 | 4038.6 | 48078 | +3.6% |
| AtomTable interning | 29000 | 4054.2 | 139798 | +1.7% |
| AtomTable lookup | 171563000 | 4000.0 | 23 | +0.0% |

**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).
