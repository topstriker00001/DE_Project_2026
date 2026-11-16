DROP SCHEMA IF EXISTS youtube CASCADE;
CREATE SCHEMA youtube;
SET search_path TO youtube;

-- 1. USERS
CREATE TABLE users (
    user_id BIGINT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    country_code CHAR(2),
    birth_year INTEGER,
    premium_until DATE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    CONSTRAINT chk_email_format CHECK (email LIKE '%@%'),
    CONSTRAINT chk_country_code_length CHECK (length(country_code) = 2),
    CONSTRAINT chk_birth_year CHECK (birth_year > 1900 AND birth_year <= extract(year from current_date))
);

-- 2. CHANNELS
CREATE TABLE channels (
    channel_id BIGINT PRIMARY KEY,
    owner_user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    handle VARCHAR(255) UNIQUE NOT NULL,
    channel_name VARCHAR(255) NOT NULL,
    country_code CHAR(2),
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    monetization_status VARCHAR(50) NOT NULL,
    subscriber_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    CONSTRAINT chk_handle_format CHECK (handle LIKE '@%'),
    CONSTRAINT chk_subscriber_count CHECK (subscriber_count >= 0),
    CONSTRAINT chk_monetization CHECK (monetization_status IN ('ELIGIBLE', 'NOT_ELIGIBLE', 'SUSPENDED'))
);

-- 3. VIDEOS
CREATE TABLE videos (
    video_id VARCHAR(11) PRIMARY KEY,
    channel_id BIGINT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100) NOT NULL,
    duration_sec INTEGER NOT NULL,
    is_short BOOLEAN NOT NULL,
    is_made_for_kids BOOLEAN NOT NULL,
    visibility VARCHAR(50) NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE NOT NULL,
    published_at TIMESTAMP WITH TIME ZONE,
    view_count BIGINT NOT NULL DEFAULT 0,
    
    CONSTRAINT chk_video_id_length CHECK (length(video_id) = 11),
    CONSTRAINT chk_duration_positive CHECK (duration_sec >= 0),
    CONSTRAINT chk_short_duration CHECK (NOT is_short OR duration_sec <= 60),
    CONSTRAINT chk_private_publish_time CHECK (visibility != 'PRIVATE' OR published_at IS NULL),
    CONSTRAINT chk_view_count CHECK (view_count >= 0)
);

-- 4. SUBSCRIPTIONS
CREATE TABLE subscriptions (
    user_id BIGINT REFERENCES users(user_id) ON DELETE CASCADE,
    channel_id BIGINT REFERENCES channels(channel_id) ON DELETE CASCADE,
    notifications VARCHAR(50) NOT NULL,
    subscribed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    PRIMARY KEY (user_id, channel_id),
    CONSTRAINT chk_notifications CHECK (notifications IN ('ALL', 'PERSONALIZED', 'NONE'))
);

-- 5. WATCH EVENTS
CREATE TABLE watch_events (
    watch_id BIGINT PRIMARY KEY,
    user_id BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
    video_id VARCHAR(11) NOT NULL REFERENCES videos(video_id) ON DELETE CASCADE,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    watch_seconds INTEGER NOT NULL,
    device VARCHAR(50) NOT NULL,
    traffic_source VARCHAR(50) NOT NULL,
    
    CONSTRAINT chk_watch_seconds CHECK (watch_seconds >= 0)
);

-- 6. VIDEO REACTIONS
CREATE TABLE video_reactions (
    user_id BIGINT REFERENCES users(user_id) ON DELETE CASCADE,
    video_id VARCHAR(11) REFERENCES videos(video_id) ON DELETE CASCADE,
    reaction VARCHAR(20) NOT NULL,
    reacted_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    PRIMARY KEY (user_id, video_id),
    CONSTRAINT chk_reaction_type CHECK (reaction IN ('LIKE', 'DISLIKE'))
);

-- 7. COMMENTS
CREATE TABLE comments (
    comment_id BIGINT PRIMARY KEY,
    video_id VARCHAR(11) NOT NULL REFERENCES videos(video_id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    parent_comment_id BIGINT REFERENCES comments(comment_id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    like_count INTEGER NOT NULL DEFAULT 0,
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    CONSTRAINT chk_reply_not_pinned CHECK (parent_comment_id IS NULL OR is_pinned = FALSE),
    CONSTRAINT chk_comment_likes CHECK (like_count >= 0)
);

-- 8. PLAYLISTS
CREATE TABLE playlists (
    playlist_id BIGINT PRIMARY KEY,
    owner_user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    visibility VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    CONSTRAINT chk_playlist_visibility CHECK (visibility IN ('PUBLIC', 'PRIVATE', 'UNLISTED'))
);

-- 9. PLAYLIST ITEMS
CREATE TABLE playlist_items (
    playlist_id BIGINT REFERENCES playlists(playlist_id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    video_id VARCHAR(11) NOT NULL REFERENCES videos(video_id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    PRIMARY KEY (playlist_id, position),
    CONSTRAINT uk_playlist_video UNIQUE (playlist_id, video_id),
    CONSTRAINT chk_position_positive CHECK (position > 0)
);

-- 10. AD IMPRESSIONS
CREATE TABLE ad_impressions (
    impression_id BIGINT PRIMARY KEY,
    watch_id BIGINT NOT NULL REFERENCES watch_events(watch_id) ON DELETE CASCADE,
    ad_format VARCHAR(50) NOT NULL,
    revenue_inr NUMERIC(10,4) NOT NULL,
    shown_at TIMESTAMP WITH TIME ZONE NOT NULL,
    
    CONSTRAINT chk_revenue_positive CHECK (revenue_inr >= 0),
    CONSTRAINT chk_ad_format CHECK (ad_format IN ('PREROLL', 'MIDROLL', 'POSTROLL', 'DISPLAY', 'BUMPER'))
);