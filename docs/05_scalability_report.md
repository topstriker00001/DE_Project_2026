# Phase 5: Scalability Testing Report

## 1. Objective

The objective of Phase 5 was to evaluate the YouTube Video Sharing database under a larger workload, measure query and write performance, inspect storage consumption, and demonstrate monthly range partitioning for the `watch_events` table.

## 2. Test Environment and Methodology

- Database: PostgreSQL 18
- Large-scale database: `youtube_large`
- Baseline database: `youtube_db`
- Query workload: 25 read queries (R01–R25) and 5 write queries (W01–W05)
- Benchmark repetitions: 3 runs per query
- Measurements: average, median, minimum, maximum execution time, and scan-node information
- Benchmark output: `benchmarks/results/large/summary.csv`
- Execution plans: `benchmarks/results/large/`

The benchmark was executed using the project's `run_benchmark.sh` script and the optimized query workload.

## 3. Large Dataset

The large dataset contains 10 tables and **12,828,190 data rows**.

| Table | Data rows |
|---|---:|
| users | 600,000 |
| channels | 60,000 |
| videos | 600,000 |
| subscriptions | 2,598,598 |
| watch_events | 4,000,000 |
| video_reactions | 1,350,452 |
| comments | 1,200,000 |
| playlists | 160,000 |
| playlist_items | 1,120,003 |
| ad_impressions | 1,139,137 |
| **Total** | **12,828,190** |

The `watch_events` data covers 18 months, from January 2025 through June 2026.

## 4. Query and Write Performance

All timings below are average execution times in milliseconds, measured over three runs.

### 4.1 Performance targets

| Workload category | Query IDs | Target |
|---|---|---:|
| Real-time / viewer-facing | R01, R02, R03, R05, R15, R21, W01, W02, W03 | Under 5 ms |
| Interactive Studio / search | R04, R06, R07, R08, R09, R13, R14, R24, W05 | Under 250 ms |
| Reports / analytics | R10, R11, R12, R16, R17, R18, R19, R20, R22, R23, R25 | Under 5,000 ms |
| Batch write | W04 | Under 2,000 ms |

### 4.2 Results summary

| Category | Slowest measured query | Average time | Target | Result |
|---|---|---:|---:|---|
| Real-time / viewer-facing | W03 | 3.548 ms | 5 ms | Pass |
| Interactive Studio / search | R13 | 85.306 ms | 250 ms | Pass |
| Reports / analytics | R19 | 324.644 ms | 5,000 ms | Pass |
| Batch write | W04 | 673.577 ms | 2,000 ms | Pass |

**All 30 measured queries satisfied their specified performance targets.**

### 4.3 Queries worth monitoring

- R13 recorded an average of 85.306 ms, but its median was 8.430 ms and maximum was 239.608 ms. This indicates noticeable run-to-run variability.
- W05 recorded an average of 20.352 ms, a median of 2.863 ms, and a maximum of 55.358 ms.
- W04, the batch write query, completed in an average of 673.577 ms, within its 2,000 ms target.
- R19 was the slowest analytics query at 324.644 ms, still comfortably below its 5,000 ms target.

These queries should receive attention in future performance tuning, especially where execution-time variability is high.

## 5. Seed vs Large Workload

The optimized seed benchmark and large benchmark were compared using their average execution times.

Some examples of the observed growth are:

| Query | Seed average (ms) | Large average (ms) | Approx. growth |
|---|---:|---:|---:|
| R04 | 1.790 | 37.915 | 21.18x |
| R10 | 1.137 | 26.381 | 23.20x |
| R13 | 0.911 | 85.306 | 93.64x |
| R19 | 39.993 | 324.644 | 8.12x |
| W04 | 21.471 | 673.577 | 31.37x |
| W05 | 0.632 | 20.352 | 32.20x |

R13's growth factor is influenced by its high measured average and run-to-run variability. Its median large-workload time was 8.430 ms, so the average should not be interpreted in isolation.

The large and seed databases do not have identical index configurations. Therefore, their database-size measurements are not a controlled comparison of data-volume growth alone.

## 6. Storage Analysis

The measured size of the large database was approximately **2,498 MB**.

Largest table storage footprints, including indexes:

| Table | Table data | Indexes | Total |
|---|---:|---:|---:|
| watch_events | 341 MB | 636 MB | 978 MB |
| subscriptions | 160 MB | 179 MB | 338 MB |
| videos | 104 MB | 154 MB | 258 MB |
| comments | 117 MB | 124 MB | 241 MB |
| ad_impressions | 74 MB | 122 MB | 197 MB |
| video_reactions | 88 MB | 105 MB | 193 MB |
| playlist_items | 64 MB | 76 MB | 141 MB |
| users | 55 MB | 62 MB | 116 MB |
| playlists | 12 MB | 3.5 MB | 16 MB |
| channels | 6 MB | 7 MB | 13 MB |

`watch_events` is the largest table and has substantial index storage. This is expected for a high-volume event table with several query-supporting indexes.

The seed database measured approximately 74 MB. Its index configuration differs from the large database, so this figure is provided as context rather than a direct like-for-like storage comparison.

## 7. Monthly Partitioning

A partitioning demonstration was implemented in the separate `youtube_scale` schema. The original `youtube.watch_events` table was not modified.

Implementation details:

- Created a range-partitioned `youtube_scale.watch_events` table using `started_at`.
- Created 18 monthly partitions from January 2025 through June 2026.
- Added a default partition for dates outside the defined monthly ranges.
- Added a registry table to preserve global `watch_id` uniqueness while using the composite partition key `(watch_id, started_at)`.
- Copied all 4,000,000 watch-event rows into the partitioned structure.
- Created an index on `started_at` with included query columns and ran `VACUUM`.

### 7.1 Verification results

| Verification | Result |
|---|---:|
| Rows inserted into partitioned table | 4,000,000 |
| Monthly partitions | 18 |
| June 2026 query partitions scanned | 1 |
| June 2026 query execution time | Approximately 9.4 ms |

### 7.2 Partition pruning

An `EXPLAIN ANALYZE` query filtering `started_at` between June 1 and July 1, 2026, scanned only:

`watch_events_2026_06`

The other monthly partitions were excluded by PostgreSQL partition pruning. This confirms that the range-partitioning design is working for the tested date-range query.

## 8. Conclusion

The large-scale benchmark successfully tested 30 read and write queries against a dataset containing more than 12.8 million rows.

All measured queries met their defined performance targets. The report also identified R13 and W05 as queries with noticeable run-to-run variability. Storage measurements showed that `watch_events` is the largest table by total footprint.

The partitioning experiment successfully organized 4 million watch events into 18 monthly partitions. The June 2026 execution plan scanned only the relevant monthly partition, demonstrating partition pruning.

Overall, Phase 5 demonstrates that the optimized database workload meets the project's stated scalability targets on the tested PostgreSQL environment. Further tuning and repeated benchmarking under controlled cache and hardware conditions would help assess performance consistency at even larger scales.
