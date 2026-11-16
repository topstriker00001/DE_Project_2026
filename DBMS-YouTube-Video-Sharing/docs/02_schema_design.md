# Phase 2: Schema Design and Data Loading

## 1. Schema Overview
The `youtube` schema consists of 10 tables designed to accurately model a video-sharing platform:
* **Core Entities:** `users`, `channels`, `videos`
* **User Interactions:** `subscriptions`, `watch_events`, `video_reactions`, `comments`
* **Collections:** `playlists`, `playlist_items`
* **Monetization:** `ad_impressions`

**Key Constraints Applied:**
* Primary Keys for unique identification.
* Foreign Keys with `ON DELETE CASCADE` and `ON DELETE SET NULL` to maintain relational integrity.
* Check constraints for business logic (e.g., positive view counts, strictly bounded visibility statuses, and valid string formats).

## 2. Data Loading
Data was successfully ingested from 10 CSV files using PostgreSQL's `\copy` command. All relational dependencies were maintained by loading independent tables (users, channels) before dependent tables (videos, comments, watch_events).

## 3. Data Integrity Checks
All required integrity checks passed successfully during validation:
1. **Time-travel anomaly check** (Watch event occurring before video upload): Passed (0 rows)
2. **Duplicate entry check** (Same video in the same playlist twice): Passed (0 rows)
3. **Privacy violation check** (Private video containing a published_at timestamp): Passed (0 rows)