-- AlloyDB for PostgreSQL Schema Design
-- Core relational data: users, posts (countdowns), follows, and structured data

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table (main user data with authentication info)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firebase_uid VARCHAR(128) UNIQUE NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    email VARCHAR(255) UNIQUE NOT NULL,
    profile_image_url TEXT,
    bio TEXT,
    is_verified BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login_at TIMESTAMP WITH TIME ZONE,
    followers_count INTEGER DEFAULT 0,
    following_count INTEGER DEFAULT 0,
    posts_count INTEGER DEFAULT 0,
    
    -- Indexes for performance
    CONSTRAINT users_username_check CHECK (LENGTH(username) >= 3),
    CONSTRAINT users_email_check CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Posts (Countdowns) table with all event data
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_name VARCHAR(200) NOT NULL,
    description TEXT,
    category VARCHAR(50) NOT NULL,
    event_date TIMESTAMP WITH TIME ZONE NOT NULL,
    image_url TEXT,
    
    -- Counters (denormalized for performance)
    participants_count INTEGER DEFAULT 0,
    likes_count INTEGER DEFAULT 0,
    comments_count INTEGER DEFAULT 0,
    views_count INTEGER DEFAULT 0,
    
    -- Recent activity counters (last 24h)
    recent_likes_count INTEGER DEFAULT 0,
    recent_comments_count INTEGER DEFAULT 0,
    recent_views_count INTEGER DEFAULT 0,
    
    -- Content status and moderation
    status VARCHAR(30) DEFAULT 'visible' CHECK (status IN ('visible', 'hidden_by_moderator', 'deleted_by_user')),
    moderation_reason TEXT,
    moderated_by UUID REFERENCES users(id),
    moderated_at TIMESTAMP WITH TIME ZONE,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Search and categorization
    hashtags TEXT[], -- Array of hashtags extracted from description
    is_featured BOOLEAN DEFAULT FALSE,
    
    -- Performance indexes
    CONSTRAINT posts_event_name_check CHECK (LENGTH(event_name) >= 3),
    CONSTRAINT posts_event_date_check CHECK (event_date > NOW())
);

-- Follows table (user relationships)
CREATE TABLE follows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure a user cannot follow themselves and prevent duplicate follows
    CONSTRAINT follows_unique UNIQUE (follower_id, following_id),
    CONSTRAINT follows_no_self_follow CHECK (follower_id != following_id)
);

-- Comments table with hierarchical structure
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    parent_comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    
    -- Counters
    likes_count INTEGER DEFAULT 0,
    replies_count INTEGER DEFAULT 0,
    
    -- Moderation
    status VARCHAR(30) DEFAULT 'visible' CHECK (status IN ('visible', 'hidden_by_moderator', 'deleted_by_user')),
    moderation_reason TEXT,
    moderated_by UUID REFERENCES users(id),
    moderated_at TIMESTAMP WITH TIME ZONE,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT comments_content_check CHECK (LENGTH(content) >= 1 AND LENGTH(content) <= 2000)
);

-- Likes table (for posts and comments)
CREATE TABLE likes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure a like is for either a post or comment, not both
    CONSTRAINT likes_target_check CHECK ((post_id IS NOT NULL AND comment_id IS NULL) OR (post_id IS NULL AND comment_id IS NOT NULL)),
    CONSTRAINT likes_unique_post UNIQUE (user_id, post_id),
    CONSTRAINT likes_unique_comment UNIQUE (user_id, comment_id)
);

-- Post participants table
CREATE TABLE post_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT post_participants_unique UNIQUE (post_id, user_id)
);

-- Post views table (for analytics)
CREATE TABLE post_views (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- Allow anonymous views
    viewed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT
);

-- Admin roles table
CREATE TABLE admin_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('super_admin', 'admin', 'moderator', 'support')),
    granted_by UUID NOT NULL REFERENCES users(id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    
    CONSTRAINT admin_roles_unique UNIQUE (user_id, role)
);

-- Moderation logs table
CREATE TABLE moderation_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_id UUID NOT NULL REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(50) NOT NULL, -- 'post', 'comment', 'user'
    target_id UUID NOT NULL,
    reason TEXT,
    severity VARCHAR(10) CHECK (severity IN ('HIGH', 'MEDIUM', 'LOW')) DEFAULT 'MEDIUM',
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Indexes for efficient querying
    INDEX idx_moderation_logs_admin_id (admin_id),
    INDEX idx_moderation_logs_target (target_type, target_id),
    INDEX idx_moderation_logs_created_at (created_at)
);

-- Create indexes for optimal performance

-- Users indexes
CREATE INDEX idx_users_firebase_uid ON users(firebase_uid);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = TRUE;

-- Posts indexes
CREATE INDEX idx_posts_creator_id ON posts(creator_id);
CREATE INDEX idx_posts_category ON posts(category);
CREATE INDEX idx_posts_event_date ON posts(event_date);
CREATE INDEX idx_posts_created_at ON posts(created_at);
CREATE INDEX idx_posts_status ON posts(status);
CREATE INDEX idx_posts_featured ON posts(is_featured) WHERE is_featured = TRUE;
CREATE INDEX idx_posts_hashtags ON posts USING GIN(hashtags);
CREATE INDEX idx_posts_trending ON posts(recent_likes_count DESC, recent_comments_count DESC, created_at DESC);

-- Follows indexes
CREATE INDEX idx_follows_follower_id ON follows(follower_id);
CREATE INDEX idx_follows_following_id ON follows(following_id);
CREATE INDEX idx_follows_created_at ON follows(created_at);

-- Comments indexes
CREATE INDEX idx_comments_post_id ON comments(post_id);
CREATE INDEX idx_comments_author_id ON comments(author_id);
CREATE INDEX idx_comments_parent_id ON comments(parent_comment_id);
CREATE INDEX idx_comments_created_at ON comments(created_at);
CREATE INDEX idx_comments_status ON comments(status);

-- Likes indexes
CREATE INDEX idx_likes_user_id ON likes(user_id);
CREATE INDEX idx_likes_post_id ON likes(post_id);
CREATE INDEX idx_likes_comment_id ON likes(comment_id);
CREATE INDEX idx_likes_created_at ON likes(created_at);

-- Post participants indexes
CREATE INDEX idx_post_participants_post_id ON post_participants(post_id);
CREATE INDEX idx_post_participants_user_id ON post_participants(user_id);

-- Post views indexes
CREATE INDEX idx_post_views_post_id ON post_views(post_id);
CREATE INDEX idx_post_views_user_id ON post_views(user_id);
CREATE INDEX idx_post_views_viewed_at ON post_views(viewed_at);

-- Admin roles indexes
CREATE INDEX idx_admin_roles_user_id ON admin_roles(user_id);
CREATE INDEX idx_admin_roles_role ON admin_roles(role);
CREATE INDEX idx_admin_roles_active ON admin_roles(is_active) WHERE is_active = TRUE;

-- Functions to update counters automatically

-- Function to update user counters
CREATE OR REPLACE FUNCTION update_user_counters()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF TG_TABLE_NAME = 'follows' THEN
            -- Update follower count for the user being followed
            UPDATE users SET followers_count = followers_count + 1 WHERE id = NEW.following_id;
            -- Update following count for the follower
            UPDATE users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
        ELSIF TG_TABLE_NAME = 'posts' THEN
            -- Update posts count for the creator
            UPDATE users SET posts_count = posts_count + 1 WHERE id = NEW.creator_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF TG_TABLE_NAME = 'follows' THEN
            -- Update follower count for the user being unfollowed
            UPDATE users SET followers_count = GREATEST(0, followers_count - 1) WHERE id = OLD.following_id;
            -- Update following count for the unfollower
            UPDATE users SET following_count = GREATEST(0, following_count - 1) WHERE id = OLD.follower_id;
        ELSIF TG_TABLE_NAME = 'posts' THEN
            -- Update posts count for the creator
            UPDATE users SET posts_count = GREATEST(0, posts_count - 1) WHERE id = OLD.creator_id;
        END IF;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Function to update post counters
CREATE OR REPLACE FUNCTION update_post_counters()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF TG_TABLE_NAME = 'likes' AND NEW.post_id IS NOT NULL THEN
            UPDATE posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
            -- Update recent likes if within last 24 hours
            UPDATE posts SET recent_likes_count = recent_likes_count + 1 WHERE id = NEW.post_id;
        ELSIF TG_TABLE_NAME = 'comments' THEN
            UPDATE posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
            UPDATE posts SET recent_comments_count = recent_comments_count + 1 WHERE id = NEW.post_id;
        ELSIF TG_TABLE_NAME = 'post_participants' THEN
            UPDATE posts SET participants_count = participants_count + 1 WHERE id = NEW.post_id;
        ELSIF TG_TABLE_NAME = 'post_views' THEN
            UPDATE posts SET views_count = views_count + 1 WHERE id = NEW.post_id;
            UPDATE posts SET recent_views_count = recent_views_count + 1 WHERE id = NEW.post_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF TG_TABLE_NAME = 'likes' AND OLD.post_id IS NOT NULL THEN
            UPDATE posts SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.post_id;
        ELSIF TG_TABLE_NAME = 'comments' THEN
            UPDATE posts SET comments_count = GREATEST(0, comments_count - 1) WHERE id = OLD.post_id;
        ELSIF TG_TABLE_NAME = 'post_participants' THEN
            UPDATE posts SET participants_count = GREATEST(0, participants_count - 1) WHERE id = OLD.post_id;
        END IF;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Function to update comment counters
CREATE OR REPLACE FUNCTION update_comment_counters()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.comment_id IS NOT NULL THEN
            UPDATE comments SET likes_count = likes_count + 1 WHERE id = NEW.comment_id;
        ELSIF NEW.parent_comment_id IS NOT NULL THEN
            UPDATE comments SET replies_count = replies_count + 1 WHERE id = NEW.parent_comment_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.comment_id IS NOT NULL THEN
            UPDATE comments SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.comment_id;
        ELSIF OLD.parent_comment_id IS NOT NULL THEN
            UPDATE comments SET replies_count = GREATEST(0, replies_count - 1) WHERE id = OLD.parent_comment_id;
        END IF;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER trigger_update_user_counters_follows
    AFTER INSERT OR DELETE ON follows
    FOR EACH ROW EXECUTE FUNCTION update_user_counters();

CREATE TRIGGER trigger_update_user_counters_posts
    AFTER INSERT OR DELETE ON posts
    FOR EACH ROW EXECUTE FUNCTION update_user_counters();

CREATE TRIGGER trigger_update_post_counters_likes
    AFTER INSERT OR DELETE ON likes
    FOR EACH ROW EXECUTE FUNCTION update_post_counters();

CREATE TRIGGER trigger_update_post_counters_comments
    AFTER INSERT OR DELETE ON comments
    FOR EACH ROW EXECUTE FUNCTION update_post_counters();

CREATE TRIGGER trigger_update_post_counters_participants
    AFTER INSERT OR DELETE ON post_participants
    FOR EACH ROW EXECUTE FUNCTION update_post_counters();

CREATE TRIGGER trigger_update_post_counters_views
    AFTER INSERT ON post_views
    FOR EACH ROW EXECUTE FUNCTION update_post_counters();

CREATE TRIGGER trigger_update_comment_counters
    AFTER INSERT OR DELETE ON likes
    FOR EACH ROW EXECUTE FUNCTION update_comment_counters();

CREATE TRIGGER trigger_update_comment_replies
    AFTER INSERT OR DELETE ON comments
    FOR EACH ROW EXECUTE FUNCTION update_comment_counters();

-- Function to reset recent counters (to be called daily via cron)
CREATE OR REPLACE FUNCTION reset_recent_counters()
RETURNS void AS $$
BEGIN
    UPDATE posts SET 
        recent_likes_count = 0,
        recent_comments_count = 0,
        recent_views_count = 0;
END;
$$ LANGUAGE plpgsql;

-- Views for common queries

-- Active users view
CREATE VIEW active_users AS
SELECT 
    u.*,
    (SELECT COUNT(*) FROM posts p WHERE p.creator_id = u.id AND p.status = 'visible') as visible_posts_count,
    (SELECT COUNT(*) FROM comments c WHERE c.author_id = u.id AND c.status = 'visible') as visible_comments_count
FROM users u
WHERE u.is_active = TRUE;

-- Trending posts view (last 24 hours)
CREATE VIEW trending_posts AS
SELECT 
    p.*,
    u.username as creator_username,
    u.display_name as creator_display_name,
    u.profile_image_url as creator_profile_image,
    (p.recent_likes_count * 3 + p.recent_comments_count * 5 + p.recent_views_count * 1) as trend_score
FROM posts p
JOIN users u ON p.creator_id = u.id
WHERE p.status = 'visible'
ORDER BY trend_score DESC, p.created_at DESC;

-- User timeline view (for followers)
CREATE VIEW user_timeline AS
SELECT 
    p.*,
    u.username as creator_username,
    u.display_name as creator_display_name,
    u.profile_image_url as creator_profile_image
FROM posts p
JOIN users u ON p.creator_id = u.id
WHERE p.status = 'visible'
ORDER BY p.created_at DESC;