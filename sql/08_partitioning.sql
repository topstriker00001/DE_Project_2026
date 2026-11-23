-- ============================================================
-- CP4: Monthly RANGE Partitioning of watch_events
-- Original youtube.watch_events remains unchanged.
-- Partitioning demonstration uses a separate schema.
-- ============================================================

DROP SCHEMA IF EXISTS youtube_scale CASCADE;
CREATE SCHEMA youtube_scale;

-- Global registry preserves globally unique watch_id.
-- This is necessary because partitioned primary keys must
-- include the partition key (started_at).

CREATE TABLE youtube_scale.watch_event_keys (
    watch_id BIGINT PRIMARY KEY,
    started_at TIMESTAMPTZ NOT NULL,
    UNIQUE (watch_id, started_at)
);

-- Partitioned parent table.
CREATE TABLE youtube_scale.watch_events (
    watch_id BIGINT NOT NULL,
    user_id BIGINT,
    video_id VARCHAR(11) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    watch_seconds INTEGER NOT NULL,
    device VARCHAR(50) NOT NULL,
    traffic_source VARCHAR(50) NOT NULL,

    CONSTRAINT pk_partitioned_watch_events
        PRIMARY KEY (watch_id, started_at),

    CONSTRAINT fk_partitioned_watch_key
        FOREIGN KEY (watch_id, started_at)
        REFERENCES youtube_scale.watch_event_keys (watch_id, started_at),

    CONSTRAINT fk_partitioned_user
        FOREIGN KEY (user_id)
        REFERENCES youtube.users(user_id) ON DELETE SET NULL,

    CONSTRAINT fk_partitioned_video
        FOREIGN KEY (video_id)
        REFERENCES youtube.videos(video_id) ON DELETE CASCADE,

    CONSTRAINT chk_partitioned_watch_seconds
        CHECK (watch_seconds >= 0)
)
PARTITION BY RANGE (started_at);

-- Create 18 monthly partitions: Jan 2025 to Jun 2026.
DO $$
DECLARE
    month_start DATE := DATE '2025-01-01';
    month_end DATE;
    start_bound TIMESTAMPTZ;
    end_bound TIMESTAMPTZ;
    partition_name TEXT;
BEGIN
    WHILE month_start < DATE '2026-07-01' LOOP
        month_end := (month_start + INTERVAL '1 month')::DATE;

        start_bound := month_start::TIMESTAMP
                       AT TIME ZONE 'Asia/Kolkata';
        end_bound := month_end::TIMESTAMP
                     AT TIME ZONE 'Asia/Kolkata';

        partition_name :=
            'watch_events_' || to_char(month_start, 'YYYY_MM');

        EXECUTE format(
            'CREATE TABLE youtube_scale.%I
             PARTITION OF youtube_scale.watch_events
             FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_bound, end_bound
        );

        month_start := month_end;
    END LOOP;
END $$;

-- Catch-all partition for dates outside the predefined range.
CREATE TABLE youtube_scale.watch_events_default
PARTITION OF youtube_scale.watch_events DEFAULT;

-- Load global keys first, then partitioned event rows.
INSERT INTO youtube_scale.watch_event_keys (watch_id, started_at)
SELECT watch_id, started_at
FROM youtube.watch_events;

INSERT INTO youtube_scale.watch_events (
    watch_id, user_id, video_id, started_at,
    watch_seconds, device, traffic_source
)
SELECT
    watch_id, user_id, video_id, started_at,
    watch_seconds, device, traffic_source
FROM youtube.watch_events;

-- Index for date-range analytics on the partitioned table.
CREATE INDEX idx_partitioned_watch_started
ON youtube_scale.watch_events (started_at)
INCLUDE (video_id, watch_seconds);

VACUUM (ANALYZE) youtube_scale.watch_events;

-- Verify total rows and partition count.
SELECT count(*) AS partitioned_events
FROM youtube_scale.watch_events;

SELECT count(*) AS monthly_partitions
FROM pg_inherits
WHERE inhparent = 'youtube_scale.watch_events'::regclass
  AND inhrelid <> 'youtube_scale.watch_events_default'::regclass;

-- Demonstrate partition pruning for June 2026.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM youtube_scale.watch_events
WHERE started_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND started_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30';

-- Primary key rule:
-- PostgreSQL requires a partitioned table's PRIMARY KEY or UNIQUE
-- constraint to include all partition key columns.
-- Therefore the event table uses (watch_id, started_at).
-- watch_event_keys preserves global uniqueness of watch_id.
--
-- In a full production migration, ad_impressions.watch_id should
-- reference watch_event_keys(watch_id), while the original table
-- and foreign keys remain untouched during this demonstration.
