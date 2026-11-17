
-- =====================================================
-- YouTube Video Sharing Database
-- Team T0146
-- Phase 2: Load CSV Data
-- =====================================================

\set ON_ERROR_STOP on

SET search_path TO youtube;

BEGIN;

-- 1. USERS
\copy youtube.users(user_id,email,display_name,country_code,birth_year,premium_until,created_at) FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 2. CHANNELS
\copy youtube.channels(channel_id,owner_user_id,handle,channel_name,country_code,is_verified,monetization_status,subscriber_count,created_at) FROM 'seed_data/channels.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 3. VIDEOS
\copy youtube.videos(video_id,channel_id,title,description,category,duration_sec,is_short,is_made_for_kids,visibility,uploaded_at,published_at,view_count) FROM 'seed_data/videos.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 4. SUBSCRIPTIONS
\copy youtube.subscriptions(user_id,channel_id,notifications,subscribed_at) FROM 'seed_data/subscriptions.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 5. WATCH EVENTS
\copy youtube.watch_events(watch_id,user_id,video_id,started_at,watch_seconds,device,traffic_source) FROM 'seed_data/watch_events.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 6. VIDEO REACTIONS
\copy youtube.video_reactions(user_id,video_id,reaction,reacted_at) FROM 'seed_data/video_reactions.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 7. COMMENTS
\copy youtube.comments(comment_id,video_id,user_id,parent_comment_id,body,like_count,is_pinned,created_at) FROM 'seed_data/comments.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 8. PLAYLISTS
\copy youtube.playlists(playlist_id,owner_user_id,title,visibility,created_at) FROM 'seed_data/playlists.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 9. PLAYLIST ITEMS
\copy youtube.playlist_items(playlist_id,position,video_id,added_at) FROM 'seed_data/playlist_items.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- 10. AD IMPRESSIONS
\copy youtube.ad_impressions(impression_id,watch_id,ad_format,revenue_inr,shown_at) FROM 'seed_data/ad_impressions.csv' WITH (FORMAT csv, HEADER true, NULL '');

COMMIT;

-- Update table statistics
ANALYZE youtube.users;
ANALYZE youtube.channels;
ANALYZE youtube.videos;
ANALYZE youtube.subscriptions;
ANALYZE youtube.watch_events;
ANALYZE youtube.video_reactions;
ANALYZE youtube.comments;
ANALYZE youtube.playlists;
ANALYZE youtube.playlist_items;
ANALYZE youtube.ad_impressions;

RESET search_path;
