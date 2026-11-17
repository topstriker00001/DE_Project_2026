# Phase 3: Baseline Timings

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| R01: Channel page: the 20 newest public videos of channel 217 | READ | 2.452 | 2.588 | 3.018 | 2.686 |
| R02: Watch page: one video with its channel | READ | 0.049 | 0.055 | 0.063 | 0.056 |
| R03: Subscriptions feed: public videos from channels user 1042 subscribes to, newest first | READ | 2.906 | 3.111 | 3.604 | 3.207 |
| R04: Search: public videos with "tutorial" in the title, most viewed first | READ | 11.248 | 11.960 | 13.620 | 12.276 |
| R05: History page: the last 50 videos user 1042 watched | READ | 4.236 | 4.303 | 4.417 | 4.319 |
| R06: Publishing service: videos scheduled to go live in the first week of July 2026 | READ | 1.594 | 1.604 | 1.626 | 1.608 |
| R07: YouTube Studio: channel 217's daily views and watch hours in June 2026 | READ | 8.377 | 8.819 | 8.888 | 8.695 |
| R08: YouTube Studio: where views of video ZkNSlUB1EOs come from | READ | 4.586 | 4.686 | 4.796 | 4.689 |
| R09: YouTube Studio: average percentage watched for each of channel 217's videos | READ | 7.900 | 8.019 | 8.242 | 8.054 |
| R10: Shorts shelf: most viewed Shorts in the last 7 days of June 2026 | READ | 7.425 | 7.438 | 7.893 | 7.585 |
| R11: Trending tab: top 5 videos per category by views in June 2026 | READ | 13.460 | 13.700 | 14.146 | 13.769 |
| R12: Growth: share of logged-out viewing per device type | READ | 10.505 | 10.634 | 10.882 | 10.674 |
| R13: Creator insights: subscribers of channel 217 who have never watched any of its videos | READ | 17.056 | 17.423 | 17.547 | 17.342 |
| R14: YouTube Studio: likes, dislikes and like ratio per video of channel 217 | READ | 7.788 | 8.041 | 10.395 | 8.741 |
| R15: Watch page: pinned comment and top 10 comments of video ZkNSlUB1EOs | READ | 1.883 | 1.921 | 2.048 | 1.951 |
| R16: Finance: ad revenue per channel in June 2026, top 20 | READ | 10.613 | 10.805 | 10.874 | 10.764 |
| R17: Partner program: NOT_ELIGIBLE channels that now have 100+ subscribers and 40+ watch hours | READ | 12.160 | 12.816 | 12.849 | 12.608 |
| R18: Child safety: "made for kids" videos that still have comments (comments must be disabled) | READ | 9.043 | 9.406 | 9.641 | 9.363 |
| R19: Partner report: for every monetized channel, its latest upload and its total views | READ | 11609.198 | 11697.129 | 12109.347 | 11805.225 |
| R20: Platform analytics: daily watch hours and running total for June 2026 | READ | 8.006 | 8.074 | 8.505 | 8.195 |
| R21: Playlist page: playlist 501 in order | READ | 0.068 | 0.071 | 0.076 | 0.072 |
| R22: Copyright team: same title and duration uploaded by more than one channel | READ | 19.169 | 19.645 | 20.707 | 19.840 |
| R23: Moderation queue: all comments, newest first, page 1,201 (25 per page) | READ | 12.873 | 12.889 | 12.960 | 12.907 |
| R24: YouTube Studio: new subscribers per month for channel 217 | READ | 2.686 | 2.732 | 2.763 | 2.727 |
| R25: Premium audit: ads that were shown to users with an active Premium membership | READ | 27.993 | 29.041 | 30.418 | 29.151 |
| W01: Upload: a new public video on channel 217 | WRITE | 0.328 | 0.336 | 0.396 | 0.353 |
| W02: Player: record a view of video ZkNSlUB1EOs by user 1042 | WRITE | 0.404 | 0.460 | 0.488 | 0.451 |
| W03: View counter: add one view to video ZkNSlUB1EOs | WRITE | 0.157 | 0.167 | 0.719 | 0.348 |
| W04: Nightly job: recompute every channel's subscriber count | WRITE | 19.441 | 22.883 | 26.861 | 23.062 |
| W05: Publishing service: make scheduled videos public once their time has come (run at 3 Jul 2026 00:00) | WRITE | 1.776 | 1.817 | 1.879 | 1.824 |
| **Total (sum of all 30)** | | | | | **12042.542** |

### Scan Types and Analysis

*   **R01 (Seq Scan on videos):** Slow baseline because lacking a foreign key index on `channel_id` forces a full table scan.
*   **R02 (Index Scan using videos_pkey \| Index Scan using channels_pkey):** Fast because primary key indexes allow direct, instant row lookups.
*   **R03 (Seq Scan on videos \| Index Scan on subscriptions & channels):** Slow because while subscriptions use an index, finding the matching videos requires sequentially scanning the entire video table.
*   **R04 (Seq Scan on videos):** Slow because filtering text titles without a specific index forces reading every row.
*   **R05 (Seq Scan on watch_events \| Index Scan on videos):** Slow because it reads all watch events to filter down to a single user.
*   **R06 (Seq Scan on videos):** Slower than needed because filtering by `published_at` dates without an index requires a sequential read.
*   **R07 (Seq Scan on watch_events \| Seq Scan on videos):** Slow due to joining and aggregating views across two large tables without targeted index support.
*   **R08 (Seq Scan on watch_events):** Slow because finding records for one specific `video_id` requires a full scan of all events.
*   **R09 (Seq Scan on watch_events \| Seq Scan on videos):** Slow because calculating percentages forces full scans across both tables.
*   **R10 (Seq Scan on watch_events \| Seq Scan on videos):** Slow because it filters dates and `is_short` flags via sequential reads.
*   **R11 (Seq Scan on watch_events \| Seq Scan on videos):** Slow because joining watch events to group top videos requires full unoptimized scans.
*   **R12 (Seq Scan on watch_events):** Slow because aggregating statistics by device type requires reading the entire table.
*   **R13 (Seq Scan on subscriptions \| watch_events \| videos):** Very slow because finding negative matches triggers full scans across three separate tables.
*   **R14 (Seq Scan on video_reactions \| Seq Scan on videos):** Slow because there is no index on `video_id` in the reactions table to instantly group likes.
*   **R15 (Seq Scan on comments):** Relatively fast due to small table size, but technically slow because it lacks an index on `video_id`.
*   **R16 (Seq Scan on watch_events \| ad_impressions \| Index Scan on videos):** Slow because joining massive ad revenue logs to watch events triggers full sequential scans.
*   **R17 (Seq Scan on watch_events \| videos \| channels):** Slow due to joining three unindexed tables to aggregate complex watch hour metrics.
*   **R18 (Seq Scan on comments \| Seq Scan on videos):** Slow because locating active comments on kids' content forces a full scan of both tables.
*   **R19 (Seq Scan on channels \| videos \| watch_events):** Extremely slow (11.8 seconds average) because joining and sorting three large tables without foreign key indexes creates massive unoptimized loops.
*   **R20 (Seq Scan on watch_events):** Slow because aggregating a running total over time requires evaluating every single row.
*   **R21 (Index Scan using playlist_items_pkey \| videos_pkey):** Fast because both tables perfectly utilize their primary key indexes for exact retrieval.
*   **R22 (Seq Scan on videos):** Slow because searching for duplicate metadata involves a self-comparison across the entire unindexed table.
*   **R23 (Seq Scan on comments):** Slow because paginating down to page 1,201 without an index on `created_at` forces the database to sort the entire table first.
*   **R24 (Seq Scan on subscriptions):** Slow because filtering subscribers by month requires scanning all subscription rows.
*   **R25 (Seq Scan on watch_events \| ad_impressions \| users):** Very slow (29.1 seconds average) because filtering ad logs against premium users requires massive unindexed full table joins.
*   **W01 (no scan):** Fast because it is a direct `INSERT` command with no prerequisites to scan.
*   **W02 (no scan):** Fast for the same reason; direct insertion into the `watch_events` table.
*   **W03 (Index Scan using videos_pkey on videos):** Fast because the `UPDATE` targets a specific video directly via its primary key index.
*   **W04 (Seq Scan on channels \| Seq Scan on subscriptions):** Very slow (23 seconds) because calculating bulk totals forces the system to fully read and update all channels.
*   **W05 (Seq Scan on videos):** Slow because filtering for scheduled videos requires reading the entire videos table without a status index.