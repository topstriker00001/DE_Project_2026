-- =====================================================================
-- Phase 4: Indexes for YouTube DBMS Workload
-- =====================================================================
SET search_path TO youtube;

-- Enable trigram extension for GIN substring/ILIKE search (R04)
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA youtube;

-- ---------------------------------------------------------------------
-- 1. VIDEOS TABLE
-- ---------------------------------------------------------------------

-- Serves: R01, R03
-- Type: Partial Composite B-tree
-- Column order: channel_id (equality/join) first, published_at DESC (sort/LIMIT) second.
-- Partial filter (visibility = 'PUBLIC') shrinks index size and skips PRIVATE/UNLISTED/SCHEDULED rows.
CREATE INDEX idx_videos_channel_public_pub
    ON videos (channel_id, published_at DESC)
    WHERE visibility = 'PUBLIC';

-- Serves: R07, R09, R13, R14, R17, R19
-- Type: Covering Composite B-tree
-- Column order: channel_id (equality/join) first, uploaded_at DESC (fast max() for R19) second.
-- INCLUDE(video_id, title, duration_sec) enables Index-Only Scans without fetching wide description TEXT.
CREATE INDEX idx_videos_channel_uploaded
    ON videos (channel_id, uploaded_at DESC)
    INCLUDE (video_id, title, duration_sec);

-- Serves: R06, W05
-- Type: Partial B-tree
-- Column order: published_at (range filter + ORDER BY).
-- Partial filter indexes only the small subset of SCHEDULED videos, speeding up both read R06 and write W05.
CREATE INDEX idx_videos_scheduled_pub
    ON videos (published_at)
    WHERE visibility = 'SCHEDULED';

-- Serves: R04
-- Type: Partial GIN (pg_trgm)
-- Reason: Leading-wildcard ILIKE '%tutorial%' cannot use a standard B-tree; gin_trgm_ops indexes 3-char trigrams.
-- Partial filter limits the GIN index to PUBLIC videos only.
-- Note: view_count is intentionally NOT indexed so W03 keeps fast PostgreSQL HOT updates.
CREATE INDEX idx_videos_title_trgm_public
    ON videos USING gin (title gin_trgm_ops)
    WHERE visibility = 'PUBLIC';

-- Serves: R10
-- Type: Partial Covering B-tree
-- Column order: video_id (join key); INCLUDE(title) allows Index-Only Scan for Shorts only.
CREATE INDEX idx_videos_shorts
    ON videos (video_id)
    INCLUDE (title)
    WHERE is_short;

-- Serves: R18
-- Type: Partial Covering B-tree
-- Column order: video_id (ORDER BY + EXISTS join); INCLUDE(title, channel_id) avoids heap fetches.
-- Partial filter indexes only videos where is_made_for_kids is TRUE.
CREATE INDEX idx_videos_kids
    ON videos (video_id)
    INCLUDE (title, channel_id)
    WHERE is_made_for_kids;

-- Serves: R22
-- Type: Covering Composite B-tree
-- Column order: (title, duration_sec) matches GROUP BY for streaming GroupAggregate;
-- channel_id included as third key for COUNT(DISTINCT channel_id) via Index-Only Scan.
CREATE INDEX idx_videos_title_duration_channel
    ON videos (title, duration_sec, channel_id);

-- ---------------------------------------------------------------------
-- 2. WATCH_EVENTS TABLE (largest table: kept to 3 multi-purpose indexes to limit W02 overhead)
-- ---------------------------------------------------------------------

-- Serves: R05, R13, R25
-- Type: Partial Covering Composite B-tree
-- Column order: user_id (equality/join) first, started_at DESC (sort + LIMIT 50 for R05) second.
-- Partial filter (user_id IS NOT NULL) excludes all logged-out watch events to save space and write cost.
-- INCLUDE(video_id, watch_seconds, watch_id) enables Index-Only Scans for R05, R13, and R25.
CREATE INDEX idx_watch_events_user_started
    ON watch_events (user_id, started_at DESC)
    INCLUDE (video_id, watch_seconds, watch_id)
    WHERE user_id IS NOT NULL;

-- Serves: R07, R08, R09, R13, R17, R19
-- Type: Covering Composite B-tree
-- Column order: video_id (equality/join) first, started_at (range filter for R07) second.
-- INCLUDE(watch_seconds, traffic_source) allows Index-Only Scans across all video-level analytics.
CREATE INDEX idx_watch_events_video_started
    ON watch_events (video_id, started_at)
    INCLUDE (watch_seconds, traffic_source);

-- Serves: R10, R11, R20
-- Type: Covering B-tree
-- Column order: started_at (date range filter for last 7 days / June 2026).
-- INCLUDE(video_id, watch_seconds) enables narrower Index-Only Scans instead of scanning the full heap.
CREATE INDEX idx_watch_events_started_at
    ON watch_events (started_at)
    INCLUDE (video_id, watch_seconds);

-- ---------------------------------------------------------------------
-- 3. SUBSCRIPTIONS TABLE
-- ---------------------------------------------------------------------

-- Serves: R13, R24, W04
-- Type: Covering Composite B-tree
-- Column order: channel_id (equality/GROUP BY) first, subscribed_at (date_trunc/ORDER BY for R24) second.
-- Primary key is (user_id, channel_id), so this reverse-leading index avoids Seq Scans by channel_id.
-- INCLUDE(user_id) enables Index-Only Scans for R13 and streaming aggregation for W04.
CREATE INDEX idx_subscriptions_channel_subscribed
    ON subscriptions (channel_id, subscribed_at)
    INCLUDE (user_id);

-- ---------------------------------------------------------------------
-- 4. VIDEO_REACTIONS TABLE
-- ---------------------------------------------------------------------

-- Serves: R14
-- Type: Covering B-tree
-- Column order: video_id (join key; PK leads with user_id so video_id lookups previously did Seq Scans).
-- INCLUDE(reaction) enables Index-Only Scan for LIKE/DISLIKE counts.
CREATE INDEX idx_video_reactions_video
    ON video_reactions (video_id)
    INCLUDE (reaction);

-- ---------------------------------------------------------------------
-- 5. COMMENTS TABLE
-- ---------------------------------------------------------------------

-- Serves: R15
-- Type: Partial Composite B-tree
-- Column order: video_id (equality) first, is_pinned DESC then like_count DESC (exact ORDER BY + LIMIT 11).
-- Partial filter (parent_comment_id IS NULL) indexes only top-level comments.
CREATE INDEX idx_comments_video_top_level
    ON comments (video_id, is_pinned DESC, like_count DESC)
    WHERE parent_comment_id IS NULL;

-- Serves: R18
-- Type: B-tree
-- Column order: video_id (semi-join EXISTS lookup from made-for-kids videos).
CREATE INDEX idx_comments_video_id
    ON comments (video_id);

-- Serves: R23
-- Type: Covering B-tree
-- Column order: created_at DESC (matches ORDER BY for pagination);
-- INCLUDE(comment_id) enables deferred-join Index-Only Scan over OFFSET 30000 without reading body TEXT.
CREATE INDEX idx_comments_created_desc
    ON comments (created_at DESC)
    INCLUDE (comment_id);

-- ---------------------------------------------------------------------
-- 6. AD_IMPRESSIONS & USERS TABLES
-- ---------------------------------------------------------------------

-- Serves: R16
-- Type: Covering B-tree
-- Column order: shown_at (June 2026 range filter); INCLUDE(watch_id, revenue_inr) enables Index-Only Scan.
CREATE INDEX idx_ad_impressions_shown_at
    ON ad_impressions (shown_at)
    INCLUDE (watch_id, revenue_inr);

-- Serves: R25
-- Type: Covering B-tree
-- Column order: watch_id (join key from premium users' watch events);
-- INCLUDE(impression_id, shown_at, revenue_inr) avoids heap lookups.
CREATE INDEX idx_ad_impressions_watch_id
    ON ad_impressions (watch_id)
    INCLUDE (impression_id, shown_at, revenue_inr);

-- Serves: R25
-- Type: Partial B-tree
-- Column order: user_id (join key) + premium_until (date comparison).
-- Partial filter (premium_until IS NOT NULL) skips all non-premium users so R25 starts from a tiny set.
CREATE INDEX idx_users_premium_active
    ON users (user_id, premium_until)
    WHERE premium_until IS NOT NULL;

-- ---------------------------------------------------------------------
-- 7. UPDATE STATISTICS & VISIBILITY MAPS (required for Index-Only Scans)
-- ---------------------------------------------------------------------
VACUUM ANALYZE;