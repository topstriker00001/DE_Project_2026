# YouTube Video Sharing Database – Schema Design

**Team Number:** T0146  
**Project:** YouTube Video Sharing Database  
**Database:** PostgreSQL 18+  
**Schema:** `youtube`

---

## 1. Database Overview

The database is designed to manage a YouTube-like video-sharing platform. It stores information about users, channels, videos, subscriptions, watch events, reactions, comments, playlists and advertisements.

The database uses a relational model with primary keys, foreign keys, unique constraints and check constraints to maintain data integrity.

The database contains 10 tables.

## 2. Tables and Data Dictionary

### 2.1 Users

Stores registered user information.

| Column | Data type | Constraints |
|---|---|---|
| user_id | INTEGER | Primary Key |
| email | TEXT | NOT NULL, UNIQUE |
| display_name | VARCHAR(150) | NOT NULL |
| country_code | CHAR(2) | CHECK |
| birth_year | SMALLINT | CHECK |
| premium_until | TIMESTAMPTZ | Nullable |
| created_at | TIMESTAMPTZ | NOT NULL |

**Purpose:** Stores user profiles and account information.

### 2.2 Channels

Stores creator channel information.

| Column | Data type | Constraints |
|---|---|---|
| channel_id | INTEGER | Primary Key |
| owner_user_id | INTEGER | Foreign Key |
| handle | VARCHAR(100) | NOT NULL, UNIQUE |
| channel_name | VARCHAR(200) | NOT NULL |
| country_code | CHAR(2) | CHECK |
| is_verified | BOOLEAN | NOT NULL |
| monetization_status | VARCHAR(30) | CHECK |
| subscriber_count | INTEGER | NOT NULL, DEFAULT 0, CHECK |
| created_at | TIMESTAMPTZ | NOT NULL |

**Purpose:** Each channel belongs to a registered user.

### 2.3 Videos

Stores video metadata and publishing information.

| Column | Data type | Constraints |
|---|---|---|
| video_id | VARCHAR(30) | Primary Key |
| channel_id | INTEGER | Foreign Key |
| title | VARCHAR(500) | NOT NULL |
| description | TEXT | Nullable |
| category | VARCHAR(50) | CHECK |
| duration_sec | INTEGER | NOT NULL, CHECK |
| is_short | BOOLEAN | NOT NULL |
| is_made_for_kids | BOOLEAN | NOT NULL |
| visibility | VARCHAR(20) | CHECK |
| uploaded_at | TIMESTAMPTZ | NOT NULL |
| published_at | TIMESTAMPTZ | Nullable |
| view_count | BIGINT | NOT NULL, DEFAULT 0, CHECK |

**Purpose:** Stores uploaded videos and their metadata.

### 2.4 Subscriptions

Stores user subscriptions to channels.

| Column | Data type | Constraints |
|---|---|---|
| user_id | INTEGER | Composite Primary Key, Foreign Key |
| channel_id | INTEGER | Composite Primary Key, Foreign Key |
| notifications | VARCHAR(20) | NOT NULL, CHECK |
| subscribed_at | TIMESTAMPTZ | NOT NULL |

**Purpose:** Records which users subscribe to which channels.

### 2.5 Watch Events

Stores individual video viewing events.

| Column | Data type | Constraints |
|---|---|---|
| watch_id | BIGINT | Primary Key |
| user_id | INTEGER | Nullable, Foreign Key |
| video_id | VARCHAR(30) | NOT NULL, Foreign Key |
| started_at | TIMESTAMPTZ | NOT NULL |
| watch_seconds | INTEGER | NOT NULL, CHECK |
| device | VARCHAR(20) | NOT NULL, CHECK |
| traffic_source | VARCHAR(30) | NOT NULL, CHECK |

**Purpose:** Records video viewing activity. User ID can be NULL for logged-out viewers.

### 2.6 Video Reactions

Stores likes and dislikes on videos.

| Column | Data type | Constraints |
|---|---|---|
| user_id | INTEGER | Composite Primary Key, Foreign Key |
| video_id | VARCHAR(30) | Composite Primary Key, Foreign Key |
| reaction | VARCHAR(10) | NOT NULL, CHECK |
| reacted_at | TIMESTAMPTZ | NOT NULL |

**Purpose:** Ensures one reaction per user per video.

### 2.7 Comments

Stores user comments and replies.

| Column | Data type | Constraints |
|---|---|---|
| comment_id | BIGINT | Primary Key |
| video_id | VARCHAR(30) | NOT NULL, Foreign Key |
| user_id | INTEGER | NOT NULL, Foreign Key |
| parent_comment_id | BIGINT | Nullable, Self Foreign Key |
| body | TEXT | NOT NULL |
| like_count | INTEGER | NOT NULL, DEFAULT 0, CHECK |
| is_pinned | BOOLEAN | NOT NULL |
| created_at | TIMESTAMPTZ | NOT NULL |

**Purpose:** Supports comments and threaded replies.

### 2.8 Playlists

Stores user-created playlists.

| Column | Data type | Constraints |
|---|---|---|
| playlist_id | INTEGER | Primary Key |
| owner_user_id | INTEGER | NOT NULL, Foreign Key |
| title | VARCHAR(300) | NOT NULL |
| visibility | VARCHAR(20) | NOT NULL, CHECK |
| created_at | TIMESTAMPTZ | NOT NULL |

**Purpose:** Allows users to organize videos into playlists.

### 2.9 Playlist Items

Stores videos added to playlists and their positions.

| Column | Data type | Constraints |
|---|---|---|
| playlist_id | INTEGER | Composite Primary Key, Foreign Key |
| position | INTEGER | Composite Primary Key, CHECK |
| video_id | VARCHAR(30) | NOT NULL, Foreign Key |
| added_at | TIMESTAMPTZ | NOT NULL |

**Purpose:** Connects playlists with videos while maintaining their order.

### 2.10 Ad Impressions

Stores advertisement impressions associated with video watches.

| Column | Data type | Constraints |
|---|---|---|
| impression_id | BIGINT | Primary Key |
| watch_id | BIGINT | NOT NULL, Foreign Key |
| ad_format | VARCHAR(20) | NOT NULL, CHECK |
| revenue_inr | NUMERIC(12,2) | NOT NULL, CHECK |
| shown_at | TIMESTAMPTZ | NOT NULL |

**Purpose:** Tracks advertisement formats and revenue.

---

## 3. Entity Relationships and Cardinality

The database contains the following major relationships:

| Parent Table | Child Table | Relationship |
|---|---|---|
| users | channels | One-to-Many |
| channels | videos | One-to-Many |
| users | subscriptions | One-to-Many |
| channels | subscriptions | One-to-Many |
| users | watch_events | One-to-Many; user optional |
| videos | watch_events | One-to-Many |
| users | video_reactions | One-to-Many |
| videos | video_reactions | One-to-Many |
| videos | comments | One-to-Many |
| users | comments | One-to-Many |
| comments | comments | Self-referencing One-to-Many |
| users | playlists | One-to-Many |
| playlists | playlist_items | One-to-Many |
| videos | playlist_items | One-to-Many |
| watch_events | ad_impressions | One-to-Many |

**Many-to-Many relationships:**

- Users and channels are connected through subscriptions.
- Users and videos are connected through video_reactions.
- Playlists and videos are connected through playlist_items.

---

## 4. ER Diagram

The ER diagram is maintained separately in:

`diagrams/er_diagram.png`

It represents all 10 entities, their primary keys, foreign keys and relationships.

---

## 5. Functional Dependencies and Normalization

The database is designed to follow relational normalization principles.

### 5.1 Functional Dependencies

| Table | Main Functional Dependency |
|---|---|
| users | user_id → all other user attributes |
| channels | channel_id → all other channel attributes |
| videos | video_id → all other video attributes |
| subscriptions | (user_id, channel_id) → notifications, subscribed_at |
| watch_events | watch_id → all other watch attributes |
| video_reactions | (user_id, video_id) → reaction, reacted_at |
| comments | comment_id → all other comment attributes |
| playlists | playlist_id → all other playlist attributes |
| playlist_items | (playlist_id, position) → video_id, added_at |
| ad_impressions | impression_id → all other impression attributes |

### 5.2 First Normal Form (1NF)

All tables use atomic column values. There are no repeating groups or multi-valued attributes stored in a single field.

### 5.3 Second Normal Form (2NF)

Tables with composite primary keys have non-key attributes dependent on the complete primary key.

For example, in subscriptions, notifications and subscribed_at depend on both user_id and channel_id.

### 5.4 Third Normal Form (3NF)

Non-key attributes are designed to depend on the key, the whole key and nothing but the key.

User, channel, video and playlist information are stored separately to avoid unnecessary duplication.

**Normalization conclusion:** The relational design targets 3NF, with primary and foreign keys maintaining entity relationships.

---

## 6. Integrity Constraints

The schema implements:

- Primary key constraints for entity identification.
- Foreign key constraints for referential integrity.
- UNIQUE constraints on users.email and channels.handle.
- NOT NULL constraints on required attributes.
- CHECK constraints for valid ranges and allowed values.
- Composite primary keys for subscriptions, video_reactions and playlist_items.

Examples of validation rules:

- Birth year must be between 1900 and 2100 when provided.
- Subscriber count and view count cannot be negative.
- Video duration must be greater than zero.
- Reaction must be LIKE or DISLIKE.
- Playlist position must be greater than zero.
- Advertisement revenue cannot be negative.
- Visibility and monetization values must belong to allowed sets.

---

## 7. Foreign Key Delete Rules

| Relationship | Delete Rule | Reason |
|---|---|---|
| channels → users | RESTRICT | Prevent deleting a user who owns a channel |
| videos → channels | RESTRICT | Prevent deleting a channel with videos |
| subscriptions → users/channels | CASCADE | Remove subscriptions when either entity is deleted |
| watch_events → users | SET NULL | Preserve anonymous watch history |
| watch_events → videos | RESTRICT | Preserve video viewing references |
| video_reactions → users/videos | CASCADE | Remove reactions with deleted entities |
| comments → users/videos | CASCADE | Remove comments with deleted entities |
| comments → parent comments | SET NULL | Preserve replies when a parent is deleted |
| playlists → users | CASCADE | Remove playlists owned by deleted users |
| playlist_items → playlists/videos | CASCADE | Remove dependent playlist entries |
| ad_impressions → watch_events | CASCADE | Remove impressions when the watch event is deleted |

---

## 8. Derived and Redundant Attributes

Some attributes represent values that could also be calculated from other data.

### subscriber_count

Stored in channels. It could be calculated by counting subscriptions for each channel. It is retained as a denormalized counter to support faster channel statistics.

### view_count

Stored in videos. It could be calculated by counting watch_events for each video. It is retained to support efficient display of video statistics.

### is_short

Stored as a Boolean attribute alongside duration_sec. It represents a video classification and may be derived from a duration rule. The field is retained to simplify filtering and querying.

These fields may require synchronization logic in later project phases to avoid inconsistent values.

---

## 9. Data Loading and Verification

The seed data was loaded using `sql/02_load_data.sql`.

The loading process:

1. Creates a transaction.
2. Loads parent tables before dependent tables.
3. Uses PostgreSQL `\copy` for CSV imports.
4. Commits the transaction.
5. Runs ANALYZE on all tables.

### 9.1 Verified Row Counts

| Table | Expected Rows | Imported Rows |
|---|---:|---:|
| users | 30,000 | 30,000 |
| channels | 3,000 | 3,000 |
| videos | 30,000 | 30,000 |
| subscriptions | 129,253 | 129,253 |
| watch_events | 200,000 | 200,000 |
| video_reactions | 67,417 | 67,417 |
| comments | 60,000 | 60,000 |
| playlists | 8,000 | 8,000 |
| playlist_items | 56,005 | 56,005 |
| ad_impressions | 57,014 | 57,014 |
| **Total** | **657,689** | **657,689** |

All ten table counts match the expected row counts.

### 9.2 Integrity Check Results

The following checks were executed after loading:

| Integrity Check | Failures |
|---|---:|
| Videos without a valid channel | 0 |
| Subscriptions without a valid user | 0 |
| Ad impressions without a valid watch event | 0 |
| Duplicate user emails | 0 |
| Duplicate channel handles | 0 |

Additional pre-load data validation also checked candidate primary keys, composite key duplicates, required fields and foreign key references.

The tested candidate keys had no duplicates, and the checked foreign key relationships had no orphan records.

---

## 10. Data Quality Observations

The seed data contains some intentionally nullable attributes:

- `users.birth_year` has missing values.
- `users.premium_until` has missing values.
- `videos.description` has missing values.
- `videos.published_at` has missing values.
- `watch_events.user_id` can be NULL for logged-out viewing sessions.
- `comments.parent_comment_id` can be NULL for top-level comments.

These fields are nullable in the schema where appropriate.

The missing values are preserved as NULL rather than replaced with arbitrary values.

---

## 11. Conclusion

The Phase 2 database schema has been created with 10 relational tables, primary keys, foreign keys, unique constraints and validation checks.

All 657,689 seed records have been imported successfully, and the verified row counts match the expected dataset sizes.

The schema provides the foundation for the next phases involving query workloads, indexing, query optimization and scalability testing.