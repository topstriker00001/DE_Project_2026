# Phase 4: Query Optimization Report

**Database:** PostgreSQL (`youtube` schema)  
**Benchmark Method:** `benchmarks/run_benchmark.sh` — 30 queries (`R01`–`R25`, `W01`–`W05`), 5 runs each inside `BEGIN ... ROLLBACK`, reporting `avg_ms`.  
**Artifacts:**
- Indexes & Statistics: `sql/05_indexes.sql`
- Rewritten Queries: `sql/06_optimized_queries.sql`
- Raw Plans: `benchmarks/results/baseline/` and `benchmarks/results/optimized/`

**Headline Result:** Total workload time dropped from **12,042.542 ms** to **127.710 ms** — a **98.9% reduction (94.3× overall speedup)**, with read queries improving by **99.1% (115.9×)**.

---

## 1. Full 30-Query Optimization Table

`Improvement % = (Before − After) / Before × 100`

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
| :--- | ---: | :--- | :--- | ---: | :--- | :---: |
| **R01** | 2.686 | Seq Scan on `videos` filtering `channel_id` & `visibility` + Sort | Partial composite index `idx_videos_channel_public_pub(channel_id, published_at DESC) WHERE visibility = 'PUBLIC'` | 0.129 | 95.2% (20.8×) | ✅ |
| **R02** | 0.056 | Already optimal PK Index Scans (`videos_pkey`, `channels_pkey`) | None required | 0.046 | 17.9% (1.2×) | ✅ |
| **R03** | 3.207 | Seq Scan on `videos` joined to user's subscriptions | Partial composite index `idx_videos_channel_public_pub` | 0.212 | 93.4% (15.1×) | ✅ |
| **R04** | 12.276 | Seq Scan on `videos` for leading-wildcard `ILIKE '%tutorial%'` | Partial `pg_trgm` GIN index `idx_videos_title_trgm_public` | 1.790 | 85.4% (6.9×) | ✅ |
| **R05** | 4.319 | Parallel Seq Scan on 200k `watch_events` + Sort for `LIMIT 50` | Partial covering index `idx_watch_events_user_started` (Index-Only Scan, 0 heap fetches) | 0.046 | 98.9% (93.9×) | ✅ |
| **R06** | 1.608 | Seq Scan on `videos` to find rare `SCHEDULED` rows | Partial index `idx_videos_scheduled_pub(published_at) WHERE visibility = 'SCHEDULED'` | 0.061 | 96.2% (26.4×) | ✅ |
| **R07** | 8.695 | Parallel Seq Scan on `watch_events` + Seq Scan on `videos`; non-sargable `DATE(started_at)` | Query rewrite to sargable `timestamptz` range + covering indexes `idx_videos_channel_uploaded` & `idx_watch_events_video_started` | 0.104 | 98.8% (83.6×) | ✅ (proven) |
| **R08** | 4.689 | Parallel Seq Scan on 200k `watch_events` for a single `video_id` | Covering index `idx_watch_events_video_started` (Index-Only Scan) | 0.084 | 98.2% (55.8×) | ✅ |
| **R09** | 8.054 | Parallel Seq Scan on `watch_events` + Seq Scan on `videos` | Covering indexes `idx_videos_channel_uploaded` & `idx_watch_events_video_started` (Index-Only Scans) | 0.122 | 98.5% (66.0×) | ✅ |
| **R10** | 7.585 | Seq Scans on `watch_events` and `videos` for 7-day Shorts | Covering index `idx_watch_events_started_at` + partial covering index `idx_videos_shorts` | 1.137 | 85.0% (6.7×) | ✅ |
| **R11** | 13.769 | Seq Scans on `watch_events` and `videos` for full-month category ranking | Covering index `idx_watch_events_started_at` (Index-Only Scan on June rows; `videos` Seq Scan still optimal for all-category join) | 8.620 | 37.4% (1.6×) | ✅ |
| **R12** | 10.674 | Full Seq Scan on all 200k `watch_events` with no `WHERE` clause | None applicable (must scan every row in `watch_events`) | 10.743 | -0.6% (1.0×) | ✅ |
| **R13** | 17.342 | Seq Scans on `subscriptions`, `watch_events`, `videos` + **silent `NOT IN` `NULL` bug** | Rewrote `NOT IN` → `NOT EXISTS` anti-join + covering indexes `idx_subscriptions_channel_subscribed` & `idx_watch_events_user_started` | 0.911 | 94.7% (19.0×) | 🔧 Bug fixed (0 → 88 rows) |
| **R14** | 8.741 | Seq Scans on `video_reactions` and `videos` | Covering indexes `idx_videos_channel_uploaded` & `idx_video_reactions_video` | 0.169 | 98.1% (51.7×) | ✅ |
| **R15** | 1.951 | Seq Scan on `comments` for a single video | Index `idx_comments_video_id` (Bitmap Index Scan chosen by planner over `idx_comments_video_top_level`) | 0.056 | 97.1% (34.8×) | ✅ |
| **R16** | 10.764 | Seq Scans on `ad_impressions` and `watch_events` across full June month | Covering index `idx_ad_impressions_shown_at` (Index-Only Scan on June ads; `watch_events` still Hash Joined via Seq Scan) | 9.329 | 13.3% (1.2×) | ✅ |
| **R17** | 12.608 | Seq Scans on `channels`, `videos`, and `watch_events` | Covering indexes `idx_videos_channel_uploaded` & `idx_watch_events_video_started` (Index-Only Scans for qualifying channels) | 7.868 | 37.6% (1.6×) | ✅ |
| **R18** | 9.363 | Seq Scans on `videos` and `comments` | Partial covering index `idx_videos_kids` + `idx_comments_video_id` (Index-Only Semi-Join) | 0.551 | 94.1% (17.0×) | ✅ |
| **R19** | 11,805.225 | Two correlated subqueries executed 1,087 times (3,837,152 buffer hits) | Rewrote correlated subqueries into single-pass CTE aggregations + `LEFT JOIN` (3,650 buffer hits) | 39.993 | 99.7% (295.2×) | ✅ (proven) |
| **R20** | 8.195 | Seq Scan on `watch_events`; non-sargable `started_at::date BETWEEN` | Query rewrite to sargable `timestamptz` range + covering index `idx_watch_events_started_at` | 1.596 | 80.5% (5.1×) | ✅ (proven) |
| **R21** | 0.072 | Already optimal PK Index Scans (`playlist_items_pkey`, `videos_pkey`) | None required | 0.072 | 0.0% (1.0×) | ✅ |
| **R22** | 19.840 | Seq Scan on `videos` + full sort/hash aggregate over wide rows | Covering index `idx_videos_title_duration_channel` (Index-Only Scan) | 3.630 | 81.7% (5.5×) | ✅ |
| **R23** | 12.907 | Seq Scan on `comments` + top-N sort reading wide `body` TEXT for 30,025 rows | Deferred-join rewrite + covering index `idx_comments_created_desc` (skips 30k rows in index, fetches only 25 heap rows) | 1.535 | 88.1% (8.4×) | ✅ (proven) |
| **R24** | 2.727 | Seq Scan on `subscriptions` (PK leads with `user_id`, not `channel_id`) | Covering index `idx_subscriptions_channel_subscribed` (Index-Only Scan) | 0.131 | 95.2% (20.8×) | ✅ |
| **R25** | 29.151 | Seq Scans on `users`, `watch_events`, and `ad_impressions` | Rewrote with explicit `u.premium_until IS NOT NULL` + partial index `idx_users_premium_active` (planner uses Index-Only Scan on `users`, Hash Joins on `watch_events`/`ad_impressions`) | 14.727 | 49.5% (2.0×) | ✅ (proven) |
| **W01** | 0.353 | Single-row `INSERT` into `videos` | Write overhead from 7 secondary indexes on `videos` | 0.779 | -120.7% (0.5×) | ✅ |
| **W02** | 0.451 | Single-row `INSERT` into `watch_events` | Write overhead from 3 secondary indexes on `watch_events` | 0.637 | -41.2% (0.7×) | ✅ |
| **W03** | 0.348 | PK `UPDATE` on `videos.view_count` | Slight update overhead (`view_count` intentionally unindexed to preserve HOT updates where page space permits) | 0.529 | -52.0% (0.7×) | ✅ |
| **W04** | 23.062 | Bulk `UPDATE` on `channels` from `subscriptions` aggregation | Minor improvement from fresh stats & `VACUUM ANALYZE` | 21.471 | 6.9% (1.1×) | ✅ |
| **W05** | 1.824 | Seq Scan on `videos` to find `SCHEDULED` rows to publish | Partial index `idx_videos_scheduled_pub` (Bitmap Index Scan) | 0.632 | 65.4% (2.9×) | ✅ |
| **Read Subtotal (R01–R25)** | **12,016.504** | — | — | **103.662** | **99.1% (115.9×)** | — |
| **Write Subtotal (W01–W05)** | **26.038** | — | — | **24.048** | **7.6% (1.1×)** | — |
| **Total (All 30)** | **12,042.542** | — | — | **127.710** | **98.9% (94.3×)** | — |

---

## 2. Hidden SQL `NULL` Bug Found and Fixed (`R13`)

### Original Query (`R13`)
```sql
SELECT s.user_id, s.subscribed_at
FROM subscriptions s
WHERE s.channel_id = 217
  AND s.user_id NOT IN (SELECT w.user_id
                        FROM watch_events w JOIN videos v ON v.video_id = w.video_id
                        WHERE v.channel_id = 217);
```

### Why It Returns the Wrong Answer
In the schema, `watch_events.user_id` is **nullable** (`REFERENCES users(user_id) ON DELETE SET NULL`) to represent logged-out viewers. Under SQL's **three-valued logic** (`TRUE`, `FALSE`, `UNKNOWN`):
- `s.user_id NOT IN (u1, u2, ..., NULL)` is semantically equivalent to:
  `s.user_id <> u1 AND s.user_id <> u2 AND ... AND s.user_id <> NULL`.
- Because `s.user_id <> NULL` always evaluates to `UNKNOWN`, the entire `AND` expression can never evaluate to `TRUE`.
- Because channel 217 has **24 logged-out watch events** (`user_id IS NULL`), the original query silently returns **0 rows** instead of the actual non-watching subscribers.

### Fixed Query (`sql/06_optimized_queries.sql`)
```sql
SELECT s.user_id, s.subscribed_at
FROM subscriptions s
WHERE s.channel_id = 217
  AND NOT EXISTS (
      SELECT 1
      FROM watch_events w
      JOIN videos v ON v.video_id = w.video_id
      WHERE v.channel_id = 217
        AND w.user_id = s.user_id
  );
```

### Empirical Verification Output
```text
  check_name  | null_views_on_ch217 | orig_not_in_rows | fixed_not_exists_rows
--------------+---------------------+------------------+-----------------------
 R13_NULL_BUG |                  24 |                0 |                    88
(1 row)
```
`NOT EXISTS` evaluates row-matching existence rather than comparing against `NULL`, accurately returning all **88** subscribers of channel 217 who have never watched any of its videos (while also enabling an index anti-join that cuts runtime from **17.342 ms** to **0.911 ms**).

---

## 3. Result Equivalence Proofs for Rewritten Queries

All five behavior-preserving rewrites (`R07`, `R19`, `R20`, `R23`, `R25`) were verified against the live PostgreSQL dataset using symmetric multiset difference:

```sql
(SELECT * FROM orig EXCEPT ALL SELECT * FROM opt)
UNION ALL
(SELECT * FROM opt EXCEPT ALL SELECT * FROM orig)
```

| Query | Rewrite Summary | Original Row Count | Optimized Row Count | Differing Rows (`EXCEPT ALL`) | Verdict |
| :--- | :--- | ---: | ---: | ---: | :---: |
| **R07** | Replaced `DATE(w.started_at) BETWEEN` with sargable `timestamptz` range | 7 | 7 | **0** | ✅ Exact match |
| **R19** | Replaced 2 correlated subqueries with CTE aggregations + `LEFT JOIN` | 1,087 | 1,087 | **0** | ✅ Exact match |
| **R20** | Replaced `started_at::date BETWEEN` with sargable `timestamptz` range | 30 | 30 | **0** | ✅ Exact match |
| **R23** | Deferred join over covering `created_at DESC` index before heap lookup | 25 | 25 | **0** | ✅ Exact match |
| **R25** | Added explicit `u.premium_until IS NOT NULL` for partial index eligibility | 181 | 181 | **0** | ✅ Exact match |

*(Note: `R13` is intentionally not equal to the buggy baseline because the original query suffered from the `NOT IN` + `NULL` defect proven in Section 2.)*

---

## 4. Before & After `EXPLAIN ANALYZE` Plans (Top 5 Biggest Improvements)

Ranked by speedup multiplier: **R19 (295.2×)**, **R05 (93.9×)**, **R07 (83.6×)**, **R09 (66.0×)**, and **R08 (55.8×)**.

### #1 — `R19`: `11,805.225 ms` → `39.993 ms` (**99.7% / 295.2×**)
*Eliminated 1,087 correlated subplan loops scanning `videos` and `watch_events`, cutting shared buffer hits from **3,837,152** to **3,650** (**1,051× fewer buffers**).*

**Before (Baseline Run 1):**
```text
Sort  (cost=7397617.83..7397620.55 rows=1087 width=39) (actual time=11609.095..11609.127 rows=1087.00 loops=1)
  Sort Key: ((SubPlan 2)) DESC
  Sort Method: quicksort  Memory: 109kB
  Buffers: shared hit=3837152
  ->  Seq Scan on channels c  (cost=0.00..7397563.01 rows=1087 width=39) (actual time=11.819..11608.942 rows=1087.00 loops=1)
        Filter: ((monetization_status)::text = 'ELIGIBLE'::text)
        Rows Removed by Filter: 1913
        Buffers: shared hit=3837149
        SubPlan 1
          ->  Aggregate  (cost=1040.03..1040.04 rows=1 width=8) (actual time=0.719..0.719 rows=1.00 loops=1087)
                Buffers: shared hit=722855
                ->  Seq Scan on videos v  (cost=0.00..1040.00 rows=10 width=8) (actual time=0.084..0.717 rows=9.66 loops=1087)
                      Filter: (channel_id = c.channel_id)
                      Rows Removed by Filter: 29990
                      Buffers: shared hit=722855
        SubPlan 2
          ->  Aggregate  (cost=5765.37..5765.38 rows=1 width=8) (actual time=9.960..9.960 rows=1.00 loops=1087)
                Buffers: shared hit=3114255
                ->  Hash Join  (cost=1040.12..5765.20 rows=67 width=0) (actual time=1.126..9.956 rows=64.64 loops=1087)
                      Hash Cond: ((w.video_id)::text = (v_1.video_id)::text)
                      Buffers: shared hit=3114255
                      ->  Seq Scan on watch_events w  (cost=0.00..4200.00 rows=200000 width=12) (actual time=0.000..3.968 rows=200000.00 loops=1087)
                            Buffers: shared hit=2391400
                      ->  Hash  (cost=1040.00..1040.00 rows=10 width=12) (actual time=0.712..0.712 rows=9.66 loops=1087)
                            Buckets: 1024  Batches: 1  Memory Usage: 12kB
                            Buffers: shared hit=722855
                            ->  Seq Scan on videos v_1  (cost=0.00..1040.00 rows=10 width=12) (actual time=0.083..0.711 rows=9.66 loops=1087)
                                  Filter: (channel_id = c.channel_id)
                                  Rows Removed by Filter: 29990
                                  Buffers: shared hit=722855
Planning Time: 0.455 ms
Execution Time: 11609.198 ms
```

**After (Optimized Run 1):**
```text
Sort  (cost=8540.00..8542.71 rows=1087 width=39) (actual time=39.777..39.798 rows=1087.00 loops=1)
  Sort Key: (COALESCE((count(*)), '0'::bigint)) DESC
  Sort Method: quicksort  Memory: 109kB
  Buffers: shared hit=3650
  ->  Hash Right Join  (cost=8403.08..8485.18 rows=1087 width=39) (actual time=39.544..39.681 rows=1087.00 loops=1)
        Hash Cond: (v.channel_id = c.channel_id)
        Buffers: shared hit=3647
        ->  HashAggregate  (cost=7043.25..7073.24 rows=2999 width=16) (actual time=35.752..35.798 rows=1087.00 loops=1)
              Group Key: v.channel_id
              Batches: 1  Memory Usage: 153kB
              Buffers: shared hit=2904
              ->  Hash Join  (cost=1430.09..6680.91 rows=72467 width=8) (actual time=2.539..32.174 rows=70263.00 loops=1)
                    Hash Cond: (v.channel_id = c_1.channel_id)
                    Buffers: shared hit=2904
                    ->  Hash Join  (cost=1340.00..6065.08 rows=200000 width=8) (actual time=2.391..22.760 rows=200000.00 loops=1)
                          Hash Cond: ((w.video_id)::text = (v.video_id)::text)
                          Buffers: shared hit=2865
                          ->  Seq Scan on watch_events w  (cost=0.00..4200.00 rows=200000 width=12) (actual time=0.003..4.871 rows=200000.00 loops=1)
                                Buffers: shared hit=2200
                          ->  Hash  (cost=965.00..965.00 rows=30000 width=20) (actual time=2.372..2.372 rows=30000.00 loops=1)
                                Buckets: 32768  Batches: 1  Memory Usage: 1780kB
                                Buffers: shared hit=665
                                ->  Seq Scan on videos v  (cost=0.00..965.00 rows=30000 width=20) (actual time=0.001..1.002 rows=30000.00 loops=1)
                                      Buffers: shared hit=665
                    ->  Hash  (cost=76.50..76.50 rows=1087 width=8) (actual time=0.145..0.145 rows=1087.00 loops=1)
                          Buckets: 2048  Batches: 1  Memory Usage: 59kB
                          Buffers: shared hit=39
                          ->  Seq Scan on channels c_1  (cost=0.00..76.50 rows=1087 width=8) (actual time=0.002..0.108 rows=1087.00 loops=1)
                                Filter: ((monetization_status)::text = 'ELIGIBLE'::text)
                                Rows Removed by Filter: 1913
                                Buffers: shared hit=39
        ->  Hash  (cost=1346.25..1346.25 rows=1087 width=31) (actual time=3.788..3.788 rows=1087.00 loops=1)
              Buckets: 2048  Batches: 1  Memory Usage: 86kB
              Buffers: shared hit=743
              ->  Hash Right Join  (cost=1278.39..1346.25 rows=1087 width=31) (actual time=3.609..3.736 rows=1087.00 loops=1)
                    Hash Cond: (v_1.channel_id = c.channel_id)
                    Buffers: shared hit=743
                    ->  HashAggregate  (cost=1188.30..1218.29 rows=2999 width=16) (actual time=3.427..3.470 rows=1087.00 loops=1)
                          Group Key: v_1.channel_id
                          Batches: 1  Memory Usage: 153kB
                          Buffers: shared hit=704
                          ->  Hash Join  (cost=90.09..1133.95 rows=10870 width=16) (actual time=0.144..2.837 rows=10500.00 loops=1)
                                Hash Cond: (v_1.channel_id = c_2.channel_id)
                                Buffers: shared hit=704
                                ->  Seq Scan on videos v_1  (cost=0.00..965.00 rows=30000 width=16) (actual time=0.001..0.897 rows=30000.00 loops=1)
                                      Buffers: shared hit=665
                                ->  Hash  (cost=76.50..76.50 rows=1087 width=8) (actual time=0.138..0.139 rows=1087.00 loops=1)
                                      Buckets: 2048  Batches: 1  Memory Usage: 59kB
                                      Buffers: shared hit=39
                                      ->  Seq Scan on channels c_2  (cost=0.00..76.50 rows=1087 width=8) (actual time=0.001..0.104 rows=1087.00 loops=1)
                                            Filter: ((monetization_status)::text = 'ELIGIBLE'::text)
                                            Rows Removed by Filter: 1913
                                            Buffers: shared hit=39
                    ->  Hash  (cost=76.50..76.50 rows=1087 width=23) (actual time=0.179..0.179 rows=1087.00 loops=1)
                          Buckets: 2048  Batches: 1  Memory Usage: 75kB
                          Buffers: shared hit=39
                          ->  Seq Scan on channels c  (cost=0.00..76.50 rows=1087 width=23) (actual time=0.003..0.131 rows=1087.00 loops=1)
                                Filter: ((monetization_status)::text = 'ELIGIBLE'::text)
                                Rows Removed by Filter: 1913
                                Buffers: shared hit=39
Planning Time: 0.809 ms
Execution Time: 39.878 ms
```

---

### #2 — `R05`: `4.319 ms` → `0.046 ms` (**98.9% / 93.9×**)
*Replaced Parallel Seq Scan + Sort over 200,000 `watch_events` (`2,250` buffers) with a pre-sorted Index-Only Scan (`19` buffers, `Heap Fetches: 0`).*

**Before (Baseline Run 2):**
```text
Limit  (cost=4670.93..4721.15 rows=6 width=48) (actual time=3.724..4.386 rows=4.00 loops=1)
  Buffers: shared hit=2250
  ->  Nested Loop  (cost=4670.93..4721.15 rows=6 width=48) (actual time=3.723..4.385 rows=4.00 loops=1)
        Buffers: shared hit=2250
        ->  Gather Merge  (cost=4670.64..4671.32 rows=6 width=24) (actual time=3.716..4.358 rows=4.00 loops=1)
              Workers Planned: 1
              Workers Launched: 1
              Buffers: shared hit=2238
              ->  Sort  (cost=3670.63..3670.64 rows=4 width=24) (actual time=2.922..2.922 rows=2.00 loops=2)
                    Sort Key: w.started_at DESC
                    Sort Method: quicksort  Memory: 25kB
                    Buffers: shared hit=2238
                    Worker 0:  Sort Method: quicksort  Memory: 25kB
                    ->  Parallel Seq Scan on watch_events w  (cost=0.00..3670.59 rows=4 width=24) (actual time=0.337..2.908 rows=2.00 loops=2)
                          Filter: (user_id = 1042)
                          Rows Removed by Filter: 99998
                          Buffers: shared hit=2200
        ->  Index Scan using videos_pkey on videos v  (cost=0.29..8.30 rows=1 width=36) (actual time=0.006..0.006 rows=1.00 loops=4)
              Index Cond: ((video_id)::text = (w.video_id)::text)
              Index Searches: 4
              Buffers: shared hit=12
Planning Time: 0.372 ms
Execution Time: 4.417 ms
```

**After (Optimized Run 2):**
```text
Limit  (cost=0.71..58.36 rows=6 width=48) (actual time=0.014..0.025 rows=4.00 loops=1)
  Buffers: shared hit=19
  ->  Nested Loop  (cost=0.71..58.36 rows=6 width=48) (actual time=0.013..0.024 rows=4.00 loops=1)
        Buffers: shared hit=19
        ->  Index Only Scan using idx_watch_events_user_started on watch_events w  (cost=0.42..8.53 rows=6 width=24) (actual time=0.009..0.009 rows=4.00 loops=1)
              Index Cond: (user_id = 1042)
              Heap Fetches: 0
              Index Searches: 1
              Buffers: shared hit=7
        ->  Index Scan using videos_pkey on videos v  (cost=0.29..8.30 rows=1 width=36) (actual time=0.003..0.003 rows=1.00 loops=4)
              Index Cond: ((video_id)::text = (w.video_id)::text)
              Index Searches: 4
              Buffers: shared hit=12
Planning Time: 0.594 ms
Execution Time: 0.044 ms
```

---

### #3 — `R07`: `8.695 ms` → `0.104 ms` (**98.8% / 83.6×**)
*Rewrote non-sargable `DATE(started_at)` to a `timestamptz` range and indexed both join sides, cutting buffers from **3,533** to **56** with `Heap Fetches: 0`.*

**Before (Baseline Run 1):**
```text
GroupAggregate  (cost=6594.71..6594.74 rows=1 width=44) (actual time=8.066..8.776 rows=7.00 loops=1)
  Group Key: (date(w.started_at))
  Buffers: shared hit=3533
  ->  Sort  (cost=6594.71..6594.71 rows=1 width=8) (actual time=8.057..8.765 rows=8.00 loops=1)
        Sort Key: (date(w.started_at))
        Sort Method: quicksort  Memory: 25kB
        Buffers: shared hit=3533
        ->  Gather  (cost=2040.11..6594.70 rows=1 width=8) (actual time=7.455..8.753 rows=8.00 loops=1)
              Workers Planned: 1
              Workers Launched: 1
              Buffers: shared hit=3530
              ->  Hash Join  (cost=1040.11..5594.60 rows=1 width=8) (actual time=6.846..7.185 rows=4.00 loops=2)
                    Hash Cond: ((w.video_id)::text = (v.video_id)::text)
                    Buffers: shared hit=3530
                    ->  Parallel Seq Scan on watch_events w  (cost=0.00..4552.94 rows=588 width=24) (actual time=5.375..5.900 rows=5494.50 loops=2)
                          Filter: ((date(started_at) >= '2026-06-01'::date) AND (date(started_at) <= '2026-06-30'::date))
                          Rows Removed by Filter: 94506
                          Buffers: shared hit=2200
                    ->  Hash  (cost=1040.00..1040.00 rows=9 width=12) (actual time=1.150..1.150 rows=15.00 loops=2)
                          Buckets: 1024  Batches: 1  Memory Usage: 9kB
                          Buffers: shared hit=1330
                          ->  Seq Scan on videos v  (cost=0.00..1040.00 rows=9 width=12) (actual time=0.073..1.141 rows=15.00 loops=2)
                                Filter: (channel_id = 217)
                                Rows Removed by Filter: 29985
                                Buffers: shared hit=1330
Planning Time: 0.381 ms
Execution Time: 8.819 ms
```

**After (Optimized Run 3):**
```text
GroupAggregate  (cost=48.67..48.76 rows=3 width=44) (actual time=0.061..0.063 rows=7.00 loops=1)
  Group Key: (date(w.started_at))
  Buffers: shared hit=56
  ->  Sort  (cost=48.67..48.68 rows=3 width=8) (actual time=0.056..0.056 rows=8.00 loops=1)
        Sort Key: (date(w.started_at))
        Sort Method: quicksort  Memory: 25kB
        Buffers: shared hit=56
        ->  Nested Loop  (cost=0.83..48.65 rows=3 width=8) (actual time=0.015..0.047 rows=8.00 loops=1)
              Buffers: shared hit=53
              ->  Index Only Scan using idx_videos_channel_uploaded on videos v  (cost=0.41..4.57 rows=9 width=12) (actual time=0.007..0.008 rows=15.00 loops=1)
                    Index Cond: (channel_id = 217)
                    Heap Fetches: 0
                    Index Searches: 1
                    Buffers: shared hit=7
              ->  Index Only Scan using idx_watch_events_video_started on watch_events w  (cost=0.42..4.89 rows=1 width=24) (actual time=0.002..0.002 rows=0.53 loops=15)
                    Index Cond: ((video_id = (v.video_id)::text) AND (started_at >= '2026-06-01 00:00:00+05:30'::timestamp with time zone) AND (started_at < '2026-07-01 00:00:00+05:30'::timestamp with time zone))
                    Heap Fetches: 0
                    Index Searches: 15
                    Buffers: shared hit=46
Planning Time: 0.578 ms
Execution Time: 0.098 ms
```

---

### #4 — `R09`: `8.054 ms` → `0.122 ms` (**98.5% / 66.0×**)
*Replaced Parallel Hash Join over full `watch_events` and `videos` (`3,541` buffers) with a Nested Loop of two Index-Only Scans (`56` buffers, `Heap Fetches: 0`).*

**Before (Baseline Run 1):**
```text
Sort  (cost=5729.22..5729.24 rows=9 width=76) (actual time=7.330..7.971 rows=12.00 loops=1)
  Sort Key: (round((100.0 * avg(((w.watch_seconds)::numeric / (v.duration_sec)::numeric))), 1)) DESC
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=3541
  ->  Finalize GroupAggregate  (cost=5726.36..5729.08 rows=9 width=76) (actual time=7.299..7.963 rows=12.00 loops=1)
        Group Key: v.video_id
        Buffers: shared hit=3538
        ->  Gather Merge  (cost=5726.36..5728.77 rows=15 width=76) (actual time=7.291..7.952 rows=21.00 loops=1)
              Workers Planned: 1
              Workers Launched: 1
              Buffers: shared hit=3538
              ->  Partial GroupAggregate  (cost=4726.35..4727.07 rows=9 width=76) (actual time=6.416..6.426 rows=10.50 loops=2)
                    Group Key: v.video_id
                    Buffers: shared hit=3538
                    ->  Sort  (cost=4726.35..4726.44 rows=35 width=44) (actual time=6.407..6.409 rows=48.50 loops=2)
                          Sort Key: v.video_id
                          Sort Method: quicksort  Memory: 28kB
                          Buffers: shared hit=3538
                          Worker 0:  Sort Method: quicksort  Memory: 27kB
                          ->  Hash Join  (cost=1040.11..4725.45 rows=35 width=44) (actual time=1.423..6.376 rows=48.50 loops=2)
                                Hash Cond: ((w.video_id)::text = (v.video_id)::text)
                                Buffers: shared hit=3530
                                ->  Parallel Seq Scan on watch_events w  (cost=0.00..3376.47 rows=117647 width=16) (actual time=0.002..2.593 rows=100000.00 loops=2)
                                      Buffers: shared hit=2200
                                ->  Hash  (cost=1040.00..1040.00 rows=9 width=40) (actual time=1.159..1.159 rows=15.00 loops=2)
                                      Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                      Buffers: shared hit=1330
                                      ->  Seq Scan on videos v  (cost=0.00..1040.00 rows=9 width=40) (actual time=0.067..1.155 rows=15.00 loops=2)
                                            Filter: (channel_id = 217)
                                            Rows Removed by Filter: 29985
                                            Buffers: shared hit=1330
Planning Time: 0.365 ms
Execution Time: 8.019 ms
```

**After (Optimized Run 4):**
```text
Sort  (cost=51.53..51.55 rows=9 width=76) (actual time=0.079..0.079 rows=12.00 loops=1)
  Sort Key: (round((100.0 * avg(((w.watch_seconds)::numeric / (v.duration_sec)::numeric))), 1)) DESC
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=56
  ->  HashAggregate  (cost=51.23..51.39 rows=9 width=76) (actual time=0.065..0.068 rows=12.00 loops=1)
        Group Key: v.video_id
        Batches: 1  Memory Usage: 32kB
        Buffers: shared hit=53
        ->  Nested Loop  (cost=0.83..50.33 rows=60 width=44) (actual time=0.014..0.045 rows=97.00 loops=1)
              Buffers: shared hit=53
              ->  Index Only Scan using idx_videos_channel_uploaded on videos v  (cost=0.41..4.57 rows=9 width=40) (actual time=0.007..0.008 rows=15.00 loops=1)
                    Index Cond: (channel_id = 217)
                    Heap Fetches: 0
                    Index Searches: 1
                    Buffers: shared hit=7
              ->  Index Only Scan using idx_watch_events_video_started on watch_events w  (cost=0.42..5.00 rows=8 width=16) (actual time=0.002..0.002 rows=6.47 loops=15)
                    Index Cond: (video_id = (v.video_id)::text)
                    Heap Fetches: 0
                    Index Searches: 15
                    Buffers: shared hit=46
Planning Time: 0.559 ms
Execution Time: 0.121 ms
```

---

### #5 — `R08`: `4.689 ms` → `0.084 ms` (**98.2% / 55.8×**)
*Replaced Parallel Seq Scan filtering out 199,986 rows (`2,241` buffers) with a 4-buffer Index-Only Scan returning the exact 14 watch events directly from `idx_watch_events_video_started`.*

**Before (Baseline Run 2):**
```text
Sort  (cost=4671.69..4671.70 rows=4 width=49) (actual time=4.080..4.645 rows=5.00 loops=1)
  Sort Key: (count(*)) DESC
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=2241
  ->  Finalize GroupAggregate  (cost=4670.66..4671.65 rows=4 width=49) (actual time=4.069..4.639 rows=5.00 loops=1)
        Group Key: traffic_source
        Buffers: shared hit=2238
        ->  Gather Merge  (cost=4670.66..4671.53 rows=7 width=49) (actual time=4.052..4.620 rows=8.00 loops=1)
              Workers Planned: 1
              Workers Launched: 1
              Buffers: shared hit=2238
              ->  Partial GroupAggregate  (cost=3670.65..3670.74 rows=4 width=49) (actual time=3.341..3.342 rows=4.00 loops=2)
                    Group Key: traffic_source
                    Buffers: shared hit=2238
                    ->  Sort  (cost=3670.65..3670.66 rows=5 width=13) (actual time=3.338..3.338 rows=7.00 loops=2)
                          Sort Key: traffic_source
                          Sort Method: quicksort  Memory: 25kB
                          Buffers: shared hit=2238
                          Worker 0:  Sort Method: quicksort  Memory: 25kB
                          ->  Parallel Seq Scan on watch_events  (cost=0.00..3670.59 rows=5 width=13) (actual time=0.331..3.312 rows=7.00 loops=2)
                                Filter: ((video_id)::text = 'ZkNSlUB1EOs'::text)
                                Rows Removed by Filter: 99993
                                Buffers: shared hit=2200
Planning Time: 0.214 ms
Execution Time: 4.686 ms
```

**After (Optimized Run 1):**
```text
Sort  (cost=8.72..8.73 rows=4 width=49) (actual time=0.046..0.046 rows=5.00 loops=1)
  Sort Key: (count(*)) DESC
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=7
  ->  HashAggregate  (cost=8.62..8.68 rows=4 width=49) (actual time=0.035..0.036 rows=5.00 loops=1)
        Group Key: traffic_source
        Batches: 1  Memory Usage: 32kB
        Buffers: shared hit=4
        ->  Index Only Scan using idx_watch_events_video_started on watch_events  (cost=0.42..8.56 rows=8 width=13) (actual time=0.022..0.023 rows=14.00 loops=1)
              Index Cond: (video_id = 'ZkNSlUB1EOs'::text)
              Heap Fetches: 0
              Index Searches: 1
              Buffers: shared hit=4
Planning Time: 0.295 ms
Execution Time: 0.085 ms
```

---

## 5. Write Overhead Analysis (`W01`–`W05`)

| Query | Operation | Before (ms) | After (ms) | Delta (ms) | Change | Cause |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| **W01** | `INSERT` into `videos` | 0.353 | 0.779 | +0.426 | 120.7% slower | Must update 4–5 matching indexes on `videos` (including `pg_trgm` GIN postings for public titles) |
| **W02** | `INSERT` into `watch_events` | 0.451 | 0.637 | +0.186 | 41.2% slower | Must insert into 3 secondary covering B-tree indexes on `watch_events` |
| **W03** | `UPDATE` `videos.view_count` | 0.348 | 0.529 | +0.181 | 52.0% slower | Minor tuple/lock overhead; `view_count` was intentionally left unindexed so PostgreSQL can perform Heap-Only Tuple (HOT) updates without touching secondary indexes |
| **W04** | Bulk `UPDATE` `channels.subscriber_count` | 23.062 | 21.471 | -1.591 | 6.9% faster | Slight improvement from `VACUUM ANALYZE` and no new secondary indexes on `channels` |
| **W05** | `UPDATE` `videos` (`SCHEDULED` → `PUBLIC`) | 1.824 | 0.632 | -1.192 | 65.4% faster | Partial index `idx_videos_scheduled_pub` locates due videos immediately instead of full-scanning `videos` |
| **Total Writes** | — | **26.038** | **24.048** | **-1.990** | **7.6% faster** | — |

**Is the trade-off acceptable?**  
Yes. A video-sharing platform like YouTube is heavily read-dominated. Adding **+0.186 ms** to a view insert (`W02`) and **+0.426 ms** to a video upload (`W01`) keeps all single-row writes well under **1 ms**, while saving **11,912.842 ms** across the read workload. Total write latency across `W01`–`W05` actually **decreased** by 7.6% because `W05` benefited directly from the partial index on scheduled videos.

---

## 6. Index Storage Overhead (`pg_relation_size`)

Measured directly from `pg_class` via `pg_relation_size` (excluding pre-existing primary key and unique constraint indexes):

| Table | Table Heap Size | Index Name | Index Size | % of Table |
| :--- | ---: | :--- | ---: | ---: |
| `ad_impressions` | 3,808 kB | `idx_ad_impressions_watch_id` | 2,784 kB | 73.1% |
| `ad_impressions` | 3,808 kB | `idx_ad_impressions_shown_at` | 2,264 kB | 59.5% |
| `comments` | 6,336 kB | `idx_comments_video_top_level` | 2,080 kB | 32.8% |
| `comments` | 6,336 kB | `idx_comments_created_desc` | 1,856 kB | 29.3% |
| `comments` | 6,336 kB | `idx_comments_video_id` | 1,152 kB | 18.2% |
| `subscriptions` | 8,192 kB | `idx_subscriptions_channel_subscribed` | 5,144 kB | 62.8% |
| `users` | 2,752 kB | `idx_users_premium_active` | 96 kB | 3.5% |
| `video_reactions` | 4,672 kB | `idx_video_reactions_video` | 2,696 kB | 57.7% |
| `videos` | 5,336 kB | `idx_videos_channel_uploaded` | 2,424 kB | 45.4% |
| `videos` | 5,336 kB | `idx_videos_title_duration_channel` | 1,744 kB | 32.7% |
| `videos` | 5,336 kB | `idx_videos_title_trgm_public` | 1,656 kB | 31.0% |
| `videos` | 5,336 kB | `idx_videos_channel_public_pub` | 824 kB | 15.4% |
| `videos` | 5,336 kB | `idx_videos_shorts` | 448 kB | 8.4% |
| `videos` | 5,336 kB | `idx_videos_kids` | 56 kB | 1.0% |
| `videos` | 5,336 kB | `idx_videos_scheduled_pub` | 16 kB | 0.3% |
| `watch_events` | 17 MB | `idx_watch_events_video_started` | 11 MB | 66.4% |
| `watch_events` | 17 MB | `idx_watch_events_user_started` | 8,632 kB | 49.0% |
| `watch_events` | 17 MB | `idx_watch_events_started_at` | 7,936 kB | 45.1% |

**Storage Highlights:**
- **Partial indexes kept storage tiny where data is selective:** `idx_videos_scheduled_pub` is only **16 kB** (0.3% of `videos`), `idx_videos_kids` is **56 kB** (1.0%), and `idx_users_premium_active` is **96 kB** (3.5% of `users`).
- **Covering indexes (`INCLUDE`) trade disk space for zero-heap I/O:** The three covering indexes on `watch_events` total ~27 MB (~160% of the 17 MB table), which is a standard OLAP/OLTP trade-off that eliminated 2,200-page sequential scans across `R05`, `R07`, `R08`, `R09`, `R10`, `R13`, `R17`, and `R20`.
- **Unused / redundant candidates noticed post-benchmark:** In the current dataset, PostgreSQL chose `idx_comments_video_id` over `idx_comments_video_top_level` for `R15` and favored a Hash Join over `idx_ad_impressions_watch_id` for `R25`. Dropping those two indexes in production would reclaim **4,864 kB** (~4.8 MB) with zero regression on this workload.

---

## 7. Queries That Could Not Be (Fully) Sped Up — and Why

1. **`R12` (`10.674 ms` → `10.743 ms`, unchanged):**  
   Computes the share of logged-out views across **every row** of `watch_events` grouped by `device` with no `WHERE` clause. Because 100% of the 200,000 rows must be read, a Sequential Scan is mathematically optimal. A dedicated covering index `(device, user_id)` would only marginally reduce scan width while increasing `W02` write overhead on every view. In production, this type of full-table dashboard metric is best served by a periodically refreshed **materialized view** or incremental rollup table.
2. **`R02` (`0.056 ms` → `0.046 ms`) and `R21` (`0.072 ms` → `0.072 ms`):**  
   Both queries already performed single-key Primary Key lookups (`videos_pkey`, `channels_pkey`, `playlist_items_pkey`) in the baseline; there was no scan bottleneck to remove.
3. **`R16` (`10.764 ms` → `9.329 ms`, 13.3%), `R11` (`13.769 ms` → `8.620 ms`, 37.4%), `R17` (`12.608 ms` → `7.868 ms`, 37.6%), and `R25` (`29.151 ms` → `14.727 ms`, 49.5%):**  
   These are **low-selectivity analytical joins** that touch a large fraction of `watch_events`, `ad_impressions`, or `videos` (e.g., an entire month of platform traffic in `R11` and `R16`, or cross-table date comparisons across all premium-eligible watch/ad pairs in `R25`). Even when one side uses an Index-Only Scan (`idx_ad_impressions_shown_at`, `idx_watch_events_started_at`, `idx_users_premium_active`), PostgreSQL's cost-based planner correctly prefers sequential scans + in-memory Hash Joins over tens of thousands of random index probes. Further speedup would require pre-aggregated daily summary tables / materialized views (refreshed hourly or nightly via `REFRESH MATERIALIZED VIEW CONCURRENTLY`) rather than additional B-tree indexes.