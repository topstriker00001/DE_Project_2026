
-- =====================================================
-- YouTube Video Sharing Database
-- Team: T0146
-- Phase 2: Schema Creation
-- PostgreSQL 18+
-- =====================================================

CREATE SCHEMA IF NOT EXISTS youtube;

SET search_path TO youtube;

-- 1. USERS
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    email TEXT NOT NULL,
    display_name VARCHAR(150) NOT NULL,
    country_code CHAR(2),
    birth_year SMALLINT,
    premium_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT users_email_unique UNIQUE (email),

    CONSTRAINT chk_users_birth_year
        CHECK (birth_year IS NULL OR birth_year BETWEEN 1900 AND 2100),

    CONSTRAINT chk_users_country
        CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$')
);

-- 2. CHANNELS
CREATE TABLE channels (
    channel_id INTEGER PRIMARY KEY,
    owner_user_id INTEGER NOT NULL,
    handle VARCHAR(100) NOT NULL,
    channel_name VARCHAR(200) NOT NULL,
    country_code CHAR(2),
    is_verified BOOLEAN NOT NULL,
    monetization_status VARCHAR(30) NOT NULL,
    subscriber_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT channels_handle_unique UNIQUE (handle),

    CONSTRAINT fk_channels_owner
        FOREIGN KEY (owner_user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_channels_monetization
        CHECK (monetization_status IN
        ('ELIGIBLE', 'NOT_ELIGIBLE', 'SUSPENDED')),

    CONSTRAINT chk_channels_subscribers
        CHECK (subscriber_count >= 0),

    CONSTRAINT chk_channels_country
        CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$')
);

-- 3. VIDEOS
CREATE TABLE videos (
    video_id VARCHAR(30) PRIMARY KEY,
    channel_id INTEGER NOT NULL,
    title VARCHAR(500) NOT NULL,
    description TEXT,
    category VARCHAR(50) NOT NULL,
    duration_sec INTEGER NOT NULL,
    is_short BOOLEAN NOT NULL,
    is_made_for_kids BOOLEAN NOT NULL,
    visibility VARCHAR(20) NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL,
    published_at TIMESTAMPTZ,
    view_count BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT fk_videos_channel
        FOREIGN KEY (channel_id)
        REFERENCES channels(channel_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_videos_duration
        CHECK (duration_sec > 0),

    CONSTRAINT chk_videos_views
        CHECK (view_count >= 0),

    CONSTRAINT chk_videos_visibility
        CHECK (visibility IN
        ('PRIVATE', 'PUBLIC', 'SCHEDULED', 'UNLISTED')),

    CONSTRAINT chk_videos_category
        CHECK (category IN
        ('Comedy', 'Cooking', 'Education', 'Film',
         'Gaming', 'Music', 'News', 'Sports',
         'Tech', 'Vlogs'))
);

-- 4. SUBSCRIPTIONS
CREATE TABLE subscriptions (
    user_id INTEGER NOT NULL,
    channel_id INTEGER NOT NULL,
    notifications VARCHAR(20) NOT NULL,
    subscribed_at TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (user_id, channel_id),

    CONSTRAINT fk_subscriptions_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_subscriptions_channel
        FOREIGN KEY (channel_id)
        REFERENCES channels(channel_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_subscriptions_notifications
        CHECK (notifications IN
        ('ALL', 'NONE', 'PERSONALIZED'))
);

-- 5. WATCH EVENTS
CREATE TABLE watch_events (
    watch_id BIGINT PRIMARY KEY,
    user_id INTEGER,
    video_id VARCHAR(30) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    watch_seconds INTEGER NOT NULL,
    device VARCHAR(20) NOT NULL,
    traffic_source VARCHAR(30) NOT NULL,

    CONSTRAINT fk_watch_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE SET NULL,

    CONSTRAINT fk_watch_video
        FOREIGN KEY (video_id)
        REFERENCES videos(video_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_watch_seconds
        CHECK (watch_seconds >= 0),

    CONSTRAINT chk_watch_device
        CHECK (device IN ('ANDROID', 'IOS', 'TV', 'WEB')),

    CONSTRAINT chk_watch_traffic
        CHECK (traffic_source IN
        ('EXTERNAL', 'HOME', 'SEARCH', 'SHORTS_FEED',
         'SUBSCRIPTION', 'SUGGESTED'))
);

-- 6. VIDEO REACTIONS
CREATE TABLE video_reactions (
    user_id INTEGER NOT NULL,
    video_id VARCHAR(30) NOT NULL,
    reaction VARCHAR(10) NOT NULL,
    reacted_at TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (user_id, video_id),

    CONSTRAINT fk_reactions_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_reactions_video
        FOREIGN KEY (video_id)
        REFERENCES videos(video_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_reactions_type
        CHECK (reaction IN ('LIKE', 'DISLIKE'))
);

-- 7. COMMENTS
CREATE TABLE comments (
    comment_id BIGINT PRIMARY KEY,
    video_id VARCHAR(30) NOT NULL,
    user_id INTEGER NOT NULL,
    parent_comment_id BIGINT,
    body TEXT NOT NULL,
    like_count INTEGER NOT NULL DEFAULT 0,
    is_pinned BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_comments_video
        FOREIGN KEY (video_id)
        REFERENCES videos(video_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_comments_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_comments_parent
        FOREIGN KEY (parent_comment_id)
        REFERENCES comments(comment_id)
        ON DELETE SET NULL,

    CONSTRAINT chk_comments_likes
        CHECK (like_count >= 0),

    CONSTRAINT chk_comments_parent
        CHECK (parent_comment_id IS NULL
               OR parent_comment_id <> comment_id)
);

-- 8. PLAYLISTS
CREATE TABLE playlists (
    playlist_id INTEGER PRIMARY KEY,
    owner_user_id INTEGER NOT NULL,
    title VARCHAR(300) NOT NULL,
    visibility VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_playlists_owner
        FOREIGN KEY (owner_user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_playlists_visibility
        CHECK (visibility IN ('PRIVATE', 'PUBLIC', 'UNLISTED'))
);

-- 9. PLAYLIST ITEMS
CREATE TABLE playlist_items (
    playlist_id INTEGER NOT NULL,
    position INTEGER NOT NULL,
    video_id VARCHAR(30) NOT NULL,
    added_at TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (playlist_id, position),

    CONSTRAINT fk_playlist_items_playlist
        FOREIGN KEY (playlist_id)
        REFERENCES playlists(playlist_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_playlist_items_video
        FOREIGN KEY (video_id)
        REFERENCES videos(video_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_playlist_position
        CHECK (position > 0)
);

-- 10. AD IMPRESSIONS
CREATE TABLE ad_impressions (
    impression_id BIGINT PRIMARY KEY,
    watch_id BIGINT NOT NULL,
    ad_format VARCHAR(20) NOT NULL,
    revenue_inr NUMERIC(12,2) NOT NULL,
    shown_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_ads_watch
        FOREIGN KEY (watch_id)
        REFERENCES watch_events(watch_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_ads_format
        CHECK (ad_format IN ('MIDROLL', 'PREROLL')),

    CONSTRAINT chk_ads_revenue
        CHECK (revenue_inr >= 0)
);

SET search_path TO public;
