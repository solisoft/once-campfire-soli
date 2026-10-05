# rbuild2, 2026-10-05

AMD Ryzen 9 9950X. Each app on CPUs 8-11 (four physical cores, SMT siblings idle) with everything it uses (Soli: SoliDB and SoliKV; Rust: its SQLite, in process); loadgen on CPUs 12-15. Same parity seed, bench/loadgen, 16 keep-alive clients, 4 s per run after a 1 s warm-up, direct listeners without compression. Every thread's affinity checked; every response 200.

| req/s (median of 3, c=16) | Rust | Soli | Soli / Rust |
|---|---:|---:|---:|
| Room page | 32,212 | 16,277 | 0.51× |
| Messages page | 33,599 | 23,170 | 0.69× |
| Sidebar | 34,609 | 59,867 | 1.73× |
| Search | 36,224 | 28,667 | 0.79× |
| Post a message | 4,333 | 6,009 | 1.39× |

Rust: once-campfire-rust 64f8635, image built from its Dockerfile (`bench/run-rust`). Soli: this repo (`bench/run`, 8 workers, native SoliDB driver, 2 s session cache). Raw runs in rust/ and soli/.
