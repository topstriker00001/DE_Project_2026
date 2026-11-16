SET search_path TO youtube;

\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true);
\copy channels FROM 'seed_data/channels.csv' WITH (FORMAT csv, HEADER true);
\copy videos FROM 'seed_data/videos.csv' WITH (FORMAT csv, HEADER true);
\copy subscriptions FROM 'seed_data/subscriptions.csv' WITH (FORMAT csv, HEADER true);
\copy watch_events FROM 'seed_data/watch_events.csv' WITH (FORMAT csv, HEADER true);
\copy video_reactions FROM 'seed_data/video_reactions.csv' WITH (FORMAT csv, HEADER true);
\copy comments FROM 'seed_data/comments.csv' WITH (FORMAT csv, HEADER true);
\copy playlists FROM 'seed_data/playlists.csv' WITH (FORMAT csv, HEADER true);
\copy playlist_items FROM 'seed_data/playlist_items.csv' WITH (FORMAT csv, HEADER true);
\copy ad_impressions FROM 'seed_data/ad_impressions.csv' WITH (FORMAT csv, HEADER true);

ANALYZE;