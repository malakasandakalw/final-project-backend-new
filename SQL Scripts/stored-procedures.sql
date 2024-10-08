CREATE OR REPLACE FUNCTION get_post_by_id(p_id UUID)
RETURNS TABLE (
    post_id UUID,
    title TEXT,
    description TEXT,
    created_at TIMESTAMPTZ,
    created_by UUID,
    media JSONB,
    thumbnail JSONB,
    categories JSONB,
    upvote_count INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id AS post_id,
        p.title,
        p.description,
        p.created_at,
        p.created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'type', pm.type,
            'media_url', pm.media_url,
            'is_thumbnail', pm.is_thumbnail
        )) FILTER (WHERE pm.media_url IS NOT NULL), '[]'::jsonb) AS media,
        jsonb_build_object(
            'type', pt.type,
            'media_url', pt.media_url
        ) AS thumbnail,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', c.id,
            'name', c.name
        )) FILTER (WHERE c.id IS NOT NULL), '[]'::jsonb) AS categories,
        COUNT(DISTINCT pu.voted_by)::int AS upvote_count
    FROM
        posts p
    LEFT JOIN
        post_media pm ON p.id = pm.post_id
    LEFT JOIN
        post_media pt ON p.id = pt.post_id AND pt.is_thumbnail = true
    LEFT JOIN
        post_categories pc ON p.id = pc.post_id
    LEFT JOIN
        categories c ON pc.category_id = c.id
    LEFT JOIN
        post_upvotes pu ON p.id = pu.post_id
    WHERE
        p.id = p_id AND p.is_active IS TRUE
    GROUP BY
        p.id, pt.type, pt.media_url;
END;
$$ LANGUAGE plpgsql;








CREATE OR REPLACE FUNCTION get_posts_by_designer(
    p_user_id UUID,
    p_categories TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'recent',
    p_search TEXT DEFAULT NULL,
    p_page_index INT DEFAULT 1,
    p_page_size INT DEFAULT 10
)
RETURNS TABLE (
    post_id UUID,
    title TEXT,
    description TEXT,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    media JSONB,
    thumbnail JSONB,
    categories JSONB,
    upvote_count INT,
    user_has_voted BOOLEAN,
    total INT
) AS $$
DECLARE
    v_designer_id UUID;
    v_category_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    SELECT id INTO v_designer_id FROM designers WHERE user_id = p_user_id;
    IF v_designer_id IS NULL THEN
        RAISE EXCEPTION 'Designer not found for the given user ID';
    END IF;

    IF p_categories IS NOT NULL AND p_categories <> '' THEN
        v_category_ids := string_to_array(p_categories, ',')::uuid[];
    ELSE
        v_category_ids := NULL;
    END IF;

    v_offset := (p_page_index - 1) * p_page_size;
    v_limit := p_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT p.id) AS total
        FROM posts p
        LEFT JOIN post_categories pc ON p.id = pc.post_id
        LEFT JOIN categories c ON pc.category_id = c.id
        WHERE p.created_by = v_designer_id
        AND p.is_active IS TRUE
        AND (v_category_ids IS NULL OR c.id = ANY(v_category_ids))
        AND (p_search IS NULL OR p_search = '' OR (p.title ILIKE '%' || p_search || '%' OR p.description ILIKE '%' || p_search || '%'))
    )
    SELECT
        p.id AS post_id,
        p.title,
        p.description,
        p.created_at,
        jsonb_build_object(
            'id', p.created_by,
            'first_name', (SELECT first_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'last_name', (SELECT last_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'profile_picture', (SELECT profile_picture FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
			'email', (SELECT email FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by))
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'type', pm.type,
            'media_url', pm.media_url,
            'is_thumbnail', pm.is_thumbnail
        )) FILTER (WHERE pm.media_url IS NOT NULL), '[]'::jsonb) AS media,
        COALESCE(
            (SELECT jsonb_build_object(
                'type', pt.type,
                'media_url', pt.media_url
            ) FROM post_media pt WHERE pt.post_id = p.id AND pt.is_thumbnail = true),
            '{}'::jsonb
        ) AS thumbnail,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', c.id,
            'name', c.name
        )) FILTER (WHERE c.id IS NOT NULL), '[]'::jsonb) AS categories,
        COUNT(DISTINCT pu.voted_by)::int AS upvote_count,
        EXISTS (SELECT 1 FROM post_upvotes pu WHERE pu.post_id = p.id AND pu.voted_by = p_user_id)::boolean AS user_has_voted,
        tc.total::int AS total
    FROM
        posts p
    LEFT JOIN
        post_media pm ON p.id = pm.post_id
    LEFT JOIN
        post_categories pc ON p.id = pc.post_id
    LEFT JOIN
        categories c ON pc.category_id = c.id
    LEFT JOIN
        post_upvotes pu ON p.id = pu.post_id
    CROSS JOIN
        total_count tc
    WHERE
        p.created_by = v_designer_id
        AND p.is_active IS TRUE
        AND (v_category_ids IS NULL OR c.id = ANY(v_category_ids))
        AND (p_search IS NULL OR p_search = '' OR (p.title ILIKE '%' || p_search || '%' OR p.description ILIKE '%' || p_search || '%'))
    GROUP BY
        p.id, tc.total
    ORDER BY
        CASE 
            WHEN p_order_by = 'most_voted' THEN COUNT(DISTINCT pu.voted_by) END DESC,
		CASE
			WHEN p_order_by = 'recent' THEN p.created_at END DESC,
		CASE
			WHEN p_order_by = 'oldest' THEN p.created_at END ASC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_posts_by_designer_id(
    v_user_id UUID,
    p_designer_id UUID,
    p_categories TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'recent',
    p_search TEXT DEFAULT NULL,
    p_page_index INT DEFAULT 1,
    p_page_size INT DEFAULT 10
)
RETURNS TABLE (
    post_id UUID,
    title TEXT,
    description TEXT,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    media JSONB,
    thumbnail JSONB,
    categories JSONB,
    upvote_count INT,
    user_has_voted BOOLEAN,
    total INT
) AS $$
DECLARE
    v_category_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    IF p_categories IS NOT NULL AND p_categories <> '' THEN
        v_category_ids := string_to_array(p_categories, ',')::uuid[];
    ELSE
        v_category_ids := NULL;
    END IF;

    v_offset := (p_page_index - 1) * p_page_size;
    v_limit := p_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT p.id) AS total
        FROM posts p
        LEFT JOIN post_categories pc ON p.id = pc.post_id
        LEFT JOIN categories c ON pc.category_id = c.id
        WHERE p.created_by = p_designer_id
        AND p.is_active IS TRUE
        AND (v_category_ids IS NULL OR c.id = ANY(v_category_ids))
        AND (p_search IS NULL OR p_search = '' OR (p.title ILIKE '%' || p_search || '%' OR p.description ILIKE '%' || p_search || '%'))
    )
    SELECT
        p.id AS post_id,
        p.title,
        p.description,
        p.created_at,
        jsonb_build_object(
            'id', p.created_by,
            'first_name', (SELECT first_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'last_name', (SELECT last_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'profile_picture', (SELECT profile_picture FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
			'email', (SELECT email FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by))
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'type', pm.type,
            'media_url', pm.media_url,
            'is_thumbnail', pm.is_thumbnail
        )) FILTER (WHERE pm.media_url IS NOT NULL), '[]'::jsonb) AS media,
        COALESCE(
            (SELECT jsonb_build_object(
                'type', pt.type,
                'media_url', pt.media_url
            ) FROM post_media pt WHERE pt.post_id = p.id AND pt.is_thumbnail = true),
            '{}'::jsonb
        ) AS thumbnail,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', c.id,
            'name', c.name
        )) FILTER (WHERE c.id IS NOT NULL), '[]'::jsonb) AS categories,
        COUNT(DISTINCT pu.voted_by)::int AS upvote_count,
        EXISTS (SELECT 1 FROM post_upvotes pu WHERE pu.post_id = p.id AND pu.voted_by = v_user_id)::boolean AS user_has_voted,
        tc.total::int AS total
    FROM
        posts p
    LEFT JOIN
        post_media pm ON p.id = pm.post_id
    LEFT JOIN
        post_categories pc ON p.id = pc.post_id
    LEFT JOIN
        categories c ON pc.category_id = c.id
    LEFT JOIN
        post_upvotes pu ON p.id = pu.post_id
    CROSS JOIN
        total_count tc
    WHERE
        p.created_by = p_designer_id
        AND p.is_active IS TRUE
        AND (v_category_ids IS NULL OR c.id = ANY(v_category_ids))
        AND (p_search IS NULL OR p_search = '' OR (p.title ILIKE '%' || p_search || '%' OR p.description ILIKE '%' || p_search || '%'))
    GROUP BY
        p.id, tc.total
    ORDER BY
        CASE 
            WHEN p_order_by = 'most_voted' THEN COUNT(DISTINCT pu.voted_by) END DESC,
		CASE
			WHEN p_order_by = 'recent' THEN p.created_at END DESC,
		CASE
			WHEN p_order_by = 'oldest' THEN p.created_at END ASC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION get_user_chats(to_user_id UUID)
RETURNS TABLE(
    user_id UUID,
    user_name TEXT,
    profile_picture TEXT,
    latest_message TEXT,
    created_at TEXT,
    unread_count INT
) AS $$
BEGIN
    RETURN QUERY
    WITH LastMessage AS (
        SELECT
            m.from_user,
            m.to_user,
            m.message AS latest_message,
            m.file_url,
            m.created_at,
            ROW_NUMBER() OVER (PARTITION BY LEAST(m.from_user, m.to_user), GREATEST(m.from_user, m.to_user) ORDER BY m.created_at DESC) AS rn
        FROM messages m
        WHERE m.to_user = to_user_id OR m.from_user = to_user_id
    ),
    UnreadCount AS (
        SELECT
            from_user,
            COUNT(*) AS unread_count
        FROM messages
        WHERE to_user = to_user_id AND is_read = FALSE
        GROUP BY from_user
    )
    SELECT
        u.id AS user_id,
        u.first_name || ' ' || u.last_name AS user_name,
        u.profile_picture AS profile_picture,
        lm.latest_message,
        lm.created_at::TEXT,
        COALESCE(uc.unread_count::INTEGER, 0) AS unread_count
    FROM LastMessage lm
    JOIN users u ON u.id = CASE WHEN lm.from_user = to_user_id THEN lm.to_user ELSE lm.from_user END
    LEFT JOIN UnreadCount uc ON uc.from_user = u.id
    WHERE lm.rn = 1
	ORDER BY lm.created_at DESC;
END; $$
LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION get_public_posts(
    p_categories TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'recent',
    p_search TEXT DEFAULT NULL,
    p_page_index INT DEFAULT 1,
    p_page_size INT DEFAULT 10
)
RETURNS TABLE (
    post_id UUID,
    title TEXT,
    description TEXT,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    media JSONB,
    thumbnail JSONB,
    categories JSONB,
    upvote_count INT,
    total INT
) AS $$
DECLARE
    v_category_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    IF p_categories IS NOT NULL AND p_categories <> '' THEN
        v_category_ids := string_to_array(p_categories, ',')::uuid[];
    END IF;

    v_offset := (p_page_index - 1) * p_page_size;
    v_limit := p_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT p.id) AS total
        FROM posts p
        LEFT JOIN post_categories pc ON p.id = pc.post_id
        LEFT JOIN categories c ON pc.category_id = c.id
        WHERE (v_category_ids IS NULL OR c.id = ANY(v_category_ids))
        AND p.is_active IS TRUE
        AND (p_search IS NULL OR p_search = '' OR (p.title ILIKE '%' || p_search || '%' OR p.description ILIKE '%' || p_search || '%'))
    )
    SELECT
        p.id AS post_id,
        p.title,
        p.description,
        p.created_at,
        jsonb_build_object(
            'id', p.created_by,
            'first_name', (SELECT first_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'last_name', (SELECT last_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'profile_picture', (SELECT profile_picture FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
			'email', (SELECT email FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by))
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'type', pm.type,
            'media_url', pm.media_url,
            'is_thumbnail', pm.is_thumbnail
        )) FILTER (WHERE pm.media_url IS NOT NULL), '[]'::jsonb) AS media,
        COALESCE(
            (SELECT jsonb_build_object(
                'type', pt.type,
                'media_url', pt.media_url
            ) FROM post_media pt WHERE pt.post_id = p.id AND pt.is_thumbnail = true),
            '{}'::jsonb
        ) AS thumbnail,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', c.id,
            'name', c.name
        )) FILTER (WHERE c.id IS NOT NULL), '[]'::jsonb) AS categories,
        COUNT(DISTINCT pu.voted_by)::int AS upvote_count,
        tc.total::int AS total
    FROM
        posts p
    LEFT JOIN
        post_media pm ON p.id = pm.post_id
    LEFT JOIN
        post_categories pc ON p.id = pc.post_id
    LEFT JOIN
        categories c ON pc.category_id = c.id
    LEFT JOIN
        post_upvotes pu ON p.id = pu.post_id
    CROSS JOIN
        total_count tc
    WHERE
        p.is_active IS TRUE AND
        (v_category_ids IS NULL OR c.id = ANY(v_category_ids))
        AND (p_search IS NULL OR p_search = '' OR (p.title ILIKE '%' || p_search || '%' OR p.description ILIKE '%' || p_search || '%'))
    GROUP BY
        p.id, tc.total
    ORDER BY
        CASE WHEN p_order_by = 'most_voted' THEN COUNT(DISTINCT pu.voted_by) END DESC,
        CASE WHEN p_order_by = 'recent' THEN p.created_at END DESC,
        CASE WHEN p_order_by = 'oldest' THEN p.created_at END ASC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION get_posts(
    p_user_id UUID,
    p_categories TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'recent',
    p_search TEXT DEFAULT NULL,
    p_page_index INT DEFAULT 1,
    p_page_size INT DEFAULT 10
)
RETURNS TABLE (
    post_id UUID,
    title TEXT,
    description TEXT,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    media JSONB,
    thumbnail JSONB,
    categories JSONB,
    upvote_count INT,
    user_has_voted BOOLEAN,
    total INT
) AS $$
DECLARE
    v_category_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    IF p_categories IS NOT NULL AND p_categories <> '' THEN
        v_category_ids := string_to_array(p_categories, ',')::uuid[];
    END IF;

    v_offset := (p_page_index - 1) * p_page_size;
    v_limit := p_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT p.id) AS total
        FROM posts p
        LEFT JOIN post_categories pc ON p.id = pc.post_id
        LEFT JOIN categories c ON pc.category_id = c.id
        WHERE (v_category_ids IS NULL OR c.id = ANY(v_category_ids))
        AND p.is_active IS TRUE
        AND (p_search IS NULL OR p_search = '' OR (p.title ILIKE '%' || p_search || '%' OR p.description ILIKE '%' || p_search || '%'))
    )
    SELECT
        p.id AS post_id,
        p.title,
        p.description,
        p.created_at,
        jsonb_build_object(
            'id', p.created_by,
            'first_name', (SELECT first_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'last_name', (SELECT last_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'profile_picture', (SELECT profile_picture FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
			'email', (SELECT email FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by))
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'type', pm.type,
            'media_url', pm.media_url,
            'is_thumbnail', pm.is_thumbnail
        )) FILTER (WHERE pm.media_url IS NOT NULL), '[]'::jsonb) AS media,
        COALESCE(
            (SELECT jsonb_build_object(
                'type', pt.type,
                'media_url', pt.media_url
            ) FROM post_media pt WHERE pt.post_id = p.id AND pt.is_thumbnail = true),
            '{}'::jsonb
        ) AS thumbnail,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', c.id,
            'name', c.name
        )) FILTER (WHERE c.id IS NOT NULL), '[]'::jsonb) AS categories,
        COUNT(DISTINCT pu.voted_by)::int AS upvote_count,
        EXISTS (SELECT 1 FROM post_upvotes pu WHERE pu.post_id = p.id AND pu.voted_by = p_user_id)::boolean AS user_has_voted,
        tc.total::int AS total
    FROM
        posts p
    LEFT JOIN
        post_media pm ON p.id = pm.post_id
    LEFT JOIN
        post_categories pc ON p.id = pc.post_id
    LEFT JOIN
        categories c ON pc.category_id = c.id
    LEFT JOIN
        post_upvotes pu ON p.id = pu.post_id
    CROSS JOIN
        total_count tc
    WHERE
        (v_category_ids IS NULL OR c.id = ANY(v_category_ids))
        AND p.is_active IS TRUE
        AND (p_search IS NULL OR p_search = '' OR (p.title ILIKE '%' || p_search || '%' OR p.description ILIKE '%' || p_search || '%'))
    GROUP BY
        p.id, tc.total
    ORDER BY
        CASE WHEN p_order_by = 'most_voted' THEN COUNT(DISTINCT pu.voted_by) END DESC,
        CASE WHEN p_order_by = 'recent' THEN p.created_at END DESC,
        CASE WHEN p_order_by = 'oldest' THEN p.created_at END ASC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION get_full_post_by_id(p_id UUID, p_user_id UUID)
RETURNS TABLE (
    post_id UUID,
    title TEXT,
    description TEXT,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    media JSONB,
    thumbnail JSONB,
    categories JSONB,
    upvote_count INT,
    user_has_voted BOOLEAN,
    user_has_followed BOOLEAN,
	created_user_id UUID
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id AS post_id,
        p.title,
        p.description,
        p.created_at,
        jsonb_build_object(
            'id', p.created_by,
            'first_name', (SELECT first_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'last_name', (SELECT last_name FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
            'profile_picture', (SELECT profile_picture FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)),
			'email', (SELECT email FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by))
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'type', pm.type,
            'media_url', pm.media_url,
            'is_thumbnail', pm.is_thumbnail
        )) FILTER (WHERE pm.media_url IS NOT NULL), '[]'::jsonb) AS media,
        jsonb_build_object(
            'type', pt.type,
            'media_url', pt.media_url
        ) AS thumbnail,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', c.id,
            'name', c.name
        )) FILTER (WHERE c.id IS NOT NULL), '[]'::jsonb) AS categories,
        COUNT(DISTINCT pu.voted_by)::int AS upvote_count,
        EXISTS (SELECT 1 FROM post_upvotes pu WHERE pu.post_id = p.id AND pu.voted_by = p_user_id)::boolean AS user_has_voted,
        EXISTS (SELECT 1 FROM followings fl WHERE fl.user_id = p_user_id AND fl.designer_id = p.created_by)::boolean AS user_has_followed,
		(SELECT id FROM users WHERE id=(SELECT user_id FROM designers WHERE id=p.created_by)) AS created_user_id
    FROM
        posts p
    LEFT JOIN
        post_media pm ON p.id = pm.post_id
    LEFT JOIN
        post_media pt ON p.id = pt.post_id AND pt.is_thumbnail = true
    LEFT JOIN
        post_categories pc ON p.id = pc.post_id
    LEFT JOIN
        categories c ON pc.category_id = c.id
    LEFT JOIN
        post_upvotes pu ON p.id = pu.post_id
    WHERE
        p.id = p_id
    GROUP BY
        p.id, pt.type, pt.media_url;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION get_public_designers(
    d_locations TEXT DEFAULT NULL,
    d_categories TEXT DEFAULT NULL,
    d_order_by TEXT DEFAULT 'name',
    d_search TEXT DEFAULT NULL,
    d_page_index INT DEFAULT 1,
    d_page_size INT DEFAULT 10
)
RETURNS TABLE (
    designer_id UUID,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    profile_picture TEXT,
    locations JSONB,
    categories JSONB,
    posts_count INT,
    follow_count INT,
    upvotes_count INT,
    total INT
) AS $$
DECLARE
    v_location_ids UUID[];
    v_category_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    IF d_locations IS NOT NULL AND d_locations <> '' THEN
        v_location_ids := string_to_array(d_locations, ',')::uuid[];
    END IF;

    IF d_categories IS NOT NULL AND d_categories <> '' THEN
        v_category_ids := string_to_array(d_categories, ',')::uuid[];
    END IF;

    v_offset := (d_page_index - 1) * d_page_size;
    v_limit := d_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT d.id) AS total
        FROM designers d
        JOIN users u ON d.user_id = u.id
        LEFT JOIN designer_assigned_categories dac ON dac.designer_id = d.id
        LEFT JOIN designer_categories dc ON dac.category_id = dc.id
        WHERE (v_location_ids IS NULL OR d.location_id = ANY(v_location_ids))
        AND (v_category_ids IS NULL OR dac.category_id = ANY(v_category_ids))
        AND (d_search IS NULL OR d_search = '' OR (u.first_name ILIKE '%' || d_search || '%' OR u.last_name ILIKE '%' || d_search || '%'))
    )
    SELECT
        d.id AS designer_id,
        u.first_name::TEXT,
        u.last_name::TEXT,
        u.email::TEXT,
        u.phone::TEXT,
        u.profile_picture::TEXT,
        jsonb_agg(DISTINCT jsonb_build_object('id', l.id, 'name', l.name)) AS locations,
        jsonb_agg(DISTINCT jsonb_build_object('id', dc.id, 'name', dc.name)) AS categories,
        (SELECT COUNT(*) FROM posts p WHERE p.created_by = d.id AND p.is_active IS TRUE)::INT AS posts_count,
        (SELECT COUNT(*) FROM followings f WHERE f.designer_id = d.id)::INT AS follow_count,
        (SELECT COUNT(*) FROM post_upvotes pu JOIN posts p ON pu.post_id = p.id WHERE p.created_by = d.id AND p.is_active IS TRUE)::INT AS upvotes_count,
        tc.total::INT
    FROM
        designers d
    JOIN
        users u ON d.user_id = u.id
    JOIN
        locations l ON d.location_id = l.id
    LEFT JOIN
        designer_assigned_categories dac ON dac.designer_id = d.id
    LEFT JOIN
        designer_categories dc ON dac.category_id = dc.id
    CROSS JOIN
        total_count tc
    WHERE
        (v_location_ids IS NULL OR d.location_id = ANY(v_location_ids))
        AND (v_category_ids IS NULL OR dac.category_id = ANY(v_category_ids))
        AND (d_search IS NULL OR d_search = '' OR (u.first_name ILIKE '%' || d_search || '%' OR u.last_name ILIKE '%' || d_search || '%'))
    GROUP BY
        d.id, u.id, tc.total
    ORDER BY
        CASE WHEN d_order_by = 'name' THEN CONCAT(u.first_name, ' ', u.last_name) END ASC,
        CASE WHEN d_order_by = 'follow_count' THEN (SELECT COUNT(*) FROM followings f WHERE f.designer_id = d.id) END DESC,
        CASE WHEN d_order_by = 'upvotes_count' THEN (SELECT COUNT(*) FROM post_upvotes pu JOIN posts p ON pu.post_id = p.id WHERE p.created_by = d.id  AND p.is_active IS TRUE) END DESC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;





CREATE OR REPLACE FUNCTION get_filtered_designers(
	d_user_id UUID,
	d_followed_only BOOLEAN DEFAULT FALSE,
    d_locations TEXT DEFAULT NULL,
    d_categories TEXT DEFAULT NULL,
    d_order_by TEXT DEFAULT 'name',
    d_search TEXT DEFAULT NULL,
    d_page_index INT DEFAULT 1,
    d_page_size INT DEFAULT 10
)
RETURNS TABLE (
    designer_id UUID,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    profile_picture TEXT,
    locations JSONB,
    categories JSONB,
    posts_count INT,
    follow_count INT,
    upvotes_count INT,
    total INT
) AS $$
DECLARE
    v_location_ids UUID[];
    v_category_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    IF d_locations IS NOT NULL AND d_locations <> '' THEN
        v_location_ids := string_to_array(d_locations, ',')::uuid[];
    END IF;

    IF d_categories IS NOT NULL AND d_categories <> '' THEN
        v_category_ids := string_to_array(d_categories, ',')::uuid[];
    END IF;

    v_offset := (d_page_index - 1) * d_page_size;
    v_limit := d_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT d.id) AS total
        FROM designers d
        JOIN users u ON d.user_id = u.id
        LEFT JOIN designer_assigned_categories dac ON dac.designer_id = d.id
        LEFT JOIN designer_categories dc ON dac.category_id = dc.id
		LEFT JOIN followings f ON d.id = f.designer_id AND f.user_id = d_user_id AND d_followed_only
        WHERE (v_location_ids IS NULL OR d.location_id = ANY(v_location_ids))
        AND (v_category_ids IS NULL OR dac.category_id = ANY(v_category_ids))
        AND (d_search IS NULL OR d_search = '' OR (u.first_name ILIKE '%' || d_search || '%' OR u.last_name ILIKE '%' || d_search || '%'))
    	AND (NOT d_followed_only OR f.user_id IS NOT NULL)
	)
    SELECT
        d.id AS designer_id,
        u.first_name::TEXT,
        u.last_name::TEXT,
        u.email::TEXT,
        u.phone::TEXT,
        u.profile_picture::TEXT,
        jsonb_agg(DISTINCT jsonb_build_object('id', l.id, 'name', l.name)) AS locations,
        jsonb_agg(DISTINCT jsonb_build_object('id', dc.id, 'name', dc.name)) AS categories,
        (SELECT COUNT(*) FROM posts p WHERE p.created_by = d.id AND p.is_active IS TRUE)::INT AS posts_count,
        (SELECT COUNT(*) FROM followings f WHERE f.designer_id = d.id)::INT AS follow_count,
        (SELECT COUNT(*) FROM post_upvotes pu JOIN posts p ON pu.post_id = p.id WHERE p.created_by = d.id AND p.is_active IS TRUE)::INT AS upvotes_count,
        tc.total::INT
    FROM
        designers d
    JOIN
        users u ON d.user_id = u.id
    JOIN
        locations l ON d.location_id = l.id
    LEFT JOIN
        designer_assigned_categories dac ON dac.designer_id = d.id
    LEFT JOIN
        designer_categories dc ON dac.category_id = dc.id
	LEFT JOIN
        followings f ON d.id = f.designer_id AND f.user_id = d_user_id AND d_followed_only
    CROSS JOIN
        total_count tc
    WHERE
        (v_location_ids IS NULL OR d.location_id = ANY(v_location_ids))
        AND (v_category_ids IS NULL OR dac.category_id = ANY(v_category_ids))
        AND (d_search IS NULL OR d_search = '' OR (u.first_name ILIKE '%' || d_search || '%' OR u.last_name ILIKE '%' || d_search || '%'))
    	AND (NOT d_followed_only OR f.user_id IS NOT NULL)
	GROUP BY
        d.id, u.id, tc.total
    ORDER BY
        CASE WHEN d_order_by = 'name' THEN CONCAT(u.first_name, ' ', u.last_name) END ASC,
        CASE WHEN d_order_by = 'follow_count' THEN (SELECT COUNT(*) FROM followings f WHERE f.designer_id = d.id) END DESC,
        CASE WHEN d_order_by = 'upvotes_count' THEN (SELECT COUNT(*) FROM post_upvotes pu JOIN posts p ON pu.post_id = p.id WHERE p.created_by = d.id AND p.is_active IS TRUE) END DESC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION get_designer_data(v_designer_id  UUID, v_user_id UUID)
RETURNS TABLE(
    user_id UUID,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    profile_picture TEXT,
    locations JSONB,
    categories JSONB,
    posts_count INT,
    follow_count INT,
    upvotes_count INT,
    user_has_followed BOOLEAN	
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.user_id AS user_id,
        u.first_name::TEXT,
        u.last_name::TEXT,
        u.email::TEXT,
        u.phone::TEXT,
        u.profile_picture::TEXT,
        jsonb_agg(DISTINCT jsonb_build_object('id', l.id, 'name', l.name)) AS locations,
        jsonb_agg(DISTINCT jsonb_build_object('id', dc.id, 'name', dc.name)) AS categories,
        (SELECT COUNT(*) FROM posts p WHERE p.created_by = d.id AND p.is_active IS TRUE)::INT AS posts_count,
        (SELECT COUNT(*) FROM followings f WHERE f.designer_id = d.id)::INT AS follow_count,
        (SELECT COUNT(*) FROM post_upvotes pu JOIN posts p ON pu.post_id = p.id WHERE p.created_by = d.id AND p.is_active IS TRUE)::INT AS upvotes_count,
        EXISTS (SELECT 1 FROM followings fl WHERE fl.user_id = v_user_id AND fl.designer_id = v_designer_id)::boolean AS user_has_followed
    FROM
        designers d
    JOIN
        users u ON d.user_id = u.id
    JOIN
        locations l ON d.location_id = l.id
    LEFT JOIN
        designer_assigned_categories dac ON dac.designer_id = d.id
    LEFT JOIN
        designer_categories dc ON dac.category_id = dc.id
    WHERE
        d.id = v_designer_id
    GROUP BY
        d.id, u.id, u.first_name, u.last_name, u.email, u.phone, u.profile_picture;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_designer_data_by_user_id(v_user_id UUID)
RETURNS TABLE(
    u_user_id UUID,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    profile_picture TEXT,
    locations JSONB,
    categories JSONB,
	vd_designer_id UUID
) AS $$
DECLARE
    v_designer_id UUID;
BEGIN
    SELECT id INTO v_designer_id FROM designers WHERE user_id = v_user_id;

    IF v_designer_id IS NULL THEN
        RAISE EXCEPTION 'Designer not found for the given user ID';
    END IF;

    RETURN QUERY
    SELECT
        d.user_id AS u_user_id,
        u.first_name::TEXT,
        u.last_name::TEXT,
        u.email::TEXT,
        u.phone::TEXT,
        u.profile_picture::TEXT,
        jsonb_agg(DISTINCT jsonb_build_object('id', l.id, 'name', l.name)) AS locations,
        jsonb_agg(DISTINCT jsonb_build_object('id', dc.id, 'name', dc.name)) AS categories,
		(SELECT id FROM designers d WHERE user_id=v_user_id) AS vd_designer_id
    FROM
        designers d
    JOIN
        users u ON d.user_id = u.id
    JOIN
        locations l ON d.location_id = l.id
    LEFT JOIN
        designer_assigned_categories dac ON dac.designer_id = d.id
    LEFT JOIN
        designer_categories dc ON dac.category_id = dc.id
    WHERE
        d.id = v_designer_id
    GROUP BY
        d.user_id, u.first_name, u.last_name, u.email, u.phone, u.profile_picture;
END;
$$ LANGUAGE plpgsql;








CREATE OR REPLACE FUNCTION get_vacancies_by_employer_id(
    p_user_id UUID,
    p_categories TEXT DEFAULT NULL,
    p_locations TEXT DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT NULL,
    p_search TEXT DEFAULT NULL,
    p_page_index INT DEFAULT 1,
    p_page_size INT DEFAULT 10
)
RETURNS TABLE (
    vacancy_id UUID,
    title TEXT,
    description TEXT,
    application_url TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    categories JSONB,
    locations JSONB,
    total INT
) AS $$
DECLARE
    v_category_ids UUID[];
    v_location_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    IF p_categories IS NOT NULL AND p_categories <> '' THEN
        v_category_ids := string_to_array(p_categories, ',')::uuid[];
    ELSE
        v_category_ids := NULL;
    END IF;

    IF p_locations IS NOT NULL AND p_locations <> '' THEN
        v_location_ids := string_to_array(p_locations, ',')::uuid[];
    ELSE
        v_location_ids := NULL;
    END IF;

    v_offset := (p_page_index - 1) * p_page_size;
    v_limit := p_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT v.id) AS total
        FROM vacancies v
        LEFT JOIN vacancy_categories vc ON v.id = vc.vacancy_id
        LEFT JOIN vacancy_locations vl ON v.id = vl.vacancy_id
        WHERE (p_is_active IS NULL OR p_is_active = FALSE OR v.is_active = p_is_active)
        AND (v_category_ids IS NULL OR vc.designer_category_id = ANY(v_category_ids))
        AND (v_location_ids IS NULL OR vl.location_id = ANY(v_location_ids))
        AND (p_search IS NULL OR p_search = '' OR (v.title ILIKE '%' || p_search || '%' OR v.description ILIKE '%' || p_search || '%'))
    )
    SELECT
        v.id AS vacancy_id,
        v.title::TEXT,
        v.description::TEXT,
        v.application_url::TEXT,
        v.is_active,
        v.created_at,
        jsonb_build_object(
            'id', v.created_by,
            'first_name', u.first_name,
            'last_name', u.last_name,
            'email', u.email,
            'phone', u.phone,
            'profile_picture', u.profile_picture
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', dc.id,
            'name', dc.name
        )) FILTER (WHERE vc.designer_category_id IS NOT NULL), '[]'::jsonb) AS categories,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', l.id,
            'name', l.name
        )) FILTER (WHERE vl.location_id IS NOT NULL), '[]'::jsonb) AS locations,
        tc.total::int AS total
    FROM
        vacancies v
    JOIN
        users u ON v.created_by = u.id
    LEFT JOIN
        vacancy_categories vc ON v.id = vc.vacancy_id
    LEFT JOIN
        designer_categories dc ON vc.designer_category_id = dc.id
    LEFT JOIN
        vacancy_locations vl ON v.id = vl.vacancy_id
    LEFT JOIN
        locations l ON vl.location_id = l.id
    CROSS JOIN
        total_count tc
    WHERE
        (p_is_active IS NULL OR p_is_active = FALSE OR v.is_active = p_is_active)
        AND (v_category_ids IS NULL OR vc.designer_category_id = ANY(v_category_ids))
        AND (v_location_ids IS NULL OR vl.location_id = ANY(v_location_ids))
        AND (p_search IS NULL OR p_search = '' OR (v.title ILIKE '%' || p_search || '%' OR v.description ILIKE '%' || p_search || '%'))
    GROUP BY
        v.id, u.id, tc.total
    ORDER BY
        v.created_at DESC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION get_full_vacancy_by_id(
    p_vacancy_id UUID
)
RETURNS TABLE (
    vacancy_id UUID,
    title TEXT,
    description TEXT,
    application_url TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    categories JSONB,
    locations JSONB,
    applications JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.id AS vacancy_id,
        v.title::TEXT,
        v.description::TEXT,
        v.application_url::TEXT,
        v.is_active,
        v.created_at,
        jsonb_build_object(
            'id', v.created_by,
            'first_name', u.first_name,
            'last_name', u.last_name,
            'email', u.email,
            'phone', u.phone,
            'profile_picture', u.profile_picture
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', dc.id,
            'name', dc.name
        )) FILTER (WHERE vc.designer_category_id IS NOT NULL), '[]'::jsonb) AS categories,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', l.id,
            'name', l.name
        )) FILTER (WHERE vl.location_id IS NOT NULL), '[]'::jsonb) AS locations,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'application_id', a.id,
            'applicant_id', a.applicant_id,
            'applicant_first_name', au.first_name,
            'applicant_last_name', au.last_name,
            'applicant_email', au.email,
            'resume_url', a.resume_url,
            'applied_at', a.applied_at
        )) FILTER (WHERE a.id IS NOT NULL), '[]'::jsonb) AS applications
    FROM
        vacancies v
    JOIN
        users u ON v.created_by = u.id
    LEFT JOIN
        vacancy_categories vc ON v.id = vc.vacancy_id
    LEFT JOIN
        designer_categories dc ON vc.designer_category_id = dc.id
    LEFT JOIN
        vacancy_locations vl ON v.id = vl.vacancy_id
    LEFT JOIN
        locations l ON vl.location_id = l.id
    LEFT JOIN
        applications a ON v.id = a.vacancy_id
    LEFT JOIN
        users au ON a.applicant_id = au.id
    WHERE
        v.id = p_vacancy_id
    GROUP BY
        v.id, u.id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_vacancy_by_id(
    p_vacancy_id UUID
)
RETURNS TABLE (
    vacancy_id UUID,
    title TEXT,
    description TEXT,
    application_url TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    categories JSONB,
    locations JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.id AS vacancy_id,
        v.title::TEXT,
        v.description::TEXT,
        v.application_url::TEXT,
        v.is_active,
        v.created_at,
        jsonb_build_object(
            'id', v.created_by,
            'first_name', u.first_name,
            'last_name', u.last_name,
            'email', u.email,
            'phone', u.phone,
            'profile_picture', u.profile_picture
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', dc.id,
            'name', dc.name
        )) FILTER (WHERE vc.designer_category_id IS NOT NULL), '[]'::jsonb) AS categories,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', l.id,
            'name', l.name
        )) FILTER (WHERE vl.location_id IS NOT NULL), '[]'::jsonb) AS locations
    FROM
        vacancies v
    JOIN
        users u ON v.created_by = u.id
    LEFT JOIN
        vacancy_categories vc ON v.id = vc.vacancy_id
    LEFT JOIN
        designer_categories dc ON vc.designer_category_id = dc.id
    LEFT JOIN
        vacancy_locations vl ON v.id = vl.vacancy_id
    LEFT JOIN
        locations l ON vl.location_id = l.id
    WHERE
        v.id = p_vacancy_id
    GROUP BY
        v.id, u.id;
END;
$$ LANGUAGE plpgsql;





CREATE OR REPLACE FUNCTION get_filtered_vacancies(
    v_user_id UUID,
    v_applied_only BOOLEAN DEFAULT FALSE,
    v_categories TEXT DEFAULT NULL,
    v_locations TEXT DEFAULT NULL,
    v_page_index INT DEFAULT 1,
    v_page_size INT DEFAULT 10
)
RETURNS TABLE (
    vacancy_id UUID,
    title TEXT,
    description TEXT,
    application_url TEXT,
    is_active BOOLEAN,
    created_by JSONB,
    created_at TIMESTAMPTZ,
    categories JSONB,
    locations JSONB,
    applied BOOLEAN,
    total INT
) AS $$
DECLARE
    v_category_ids UUID[];
    v_location_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    IF v_categories IS NOT NULL AND v_categories <> '' THEN
        v_category_ids := string_to_array(v_categories, ',')::uuid[];
    END IF;

    IF v_locations IS NOT NULL AND v_locations <> '' THEN
        v_location_ids := string_to_array(v_locations, ',')::uuid[];
    END IF;

    v_offset := (v_page_index - 1) * v_page_size;
    v_limit := v_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT v.id) AS total
        FROM vacancies v
        LEFT JOIN vacancy_categories vc ON v.id = vc.vacancy_id
        LEFT JOIN vacancy_locations vl ON v.id = vl.vacancy_id
        LEFT JOIN applications a ON v.id = a.vacancy_id AND a.applicant_id = v_user_id
        WHERE (v_category_ids IS NULL OR vc.designer_category_id = ANY(v_category_ids))
          AND (v_location_ids IS NULL OR vl.location_id = ANY(v_location_ids))
          AND (NOT v_applied_only OR a.id IS NOT NULL)
    )
    SELECT
        v.id AS vacancy_id,
        v.title::TEXT,
        v.description::TEXT,
        v.application_url::TEXT,
        v.is_active,
        jsonb_build_object(
            'id', u.id,
            'first_name', u.first_name,
            'last_name', u.last_name,
            'email', u.email,
            'phone', u.phone,
            'profile_picture', u.profile_picture
        ) AS created_by,
        v.created_at,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id', dc.id, 'name', dc.name)) FILTER (WHERE dc.id IS NOT NULL), '[]'::jsonb) AS categories,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id', l.id, 'name', l.name)) FILTER (WHERE l.id IS NOT NULL), '[]'::jsonb) AS locations,
        (EXISTS (SELECT 1 FROM applications a WHERE a.vacancy_id = v.id AND a.applicant_id = v_user_id)) AS applied,
        tc.total::INT
    FROM
        vacancies v
    LEFT JOIN
        users u ON v.created_by = u.id
    LEFT JOIN
        vacancy_categories vc ON v.id = vc.vacancy_id
    LEFT JOIN
        designer_categories dc ON vc.designer_category_id = dc.id
    LEFT JOIN
        vacancy_locations vl ON v.id = vl.vacancy_id
    LEFT JOIN
        locations l ON vl.location_id = l.id
    LEFT JOIN
        applications a ON v.id = a.vacancy_id AND a.applicant_id = v_user_id
    CROSS JOIN
        total_count tc
    WHERE
        (v_category_ids IS NULL OR vc.designer_category_id = ANY(v_category_ids))
        AND (v_location_ids IS NULL OR vl.location_id = ANY(v_location_ids))
        AND (NOT v_applied_only OR a.id IS NOT NULL)
    GROUP BY
        v.id, tc.total, u.id
    ORDER BY
        v.created_at DESC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION get_public_filtered_vacancies(
    v_categories TEXT DEFAULT NULL,
    v_locations TEXT DEFAULT NULL,
    v_page_index INT DEFAULT 1,
    v_page_size INT DEFAULT 10
)
RETURNS TABLE (
    vacancy_id UUID,
    title TEXT,
    description TEXT,
    application_url TEXT,
    is_active BOOLEAN,
    created_by JSONB,
    created_at TIMESTAMPTZ,
    categories JSONB,
    locations JSONB,
    total INT
) AS $$
DECLARE
    v_category_ids UUID[];
    v_location_ids UUID[];
    v_offset INT;
    v_limit INT;
BEGIN
    IF v_categories IS NOT NULL AND v_categories <> '' THEN
        v_category_ids := string_to_array(v_categories, ',')::uuid[];
    END IF;

    IF v_locations IS NOT NULL AND v_locations <> '' THEN
        v_location_ids := string_to_array(v_locations, ',')::uuid[];
    END IF;

    v_offset := (v_page_index - 1) * v_page_size;
    v_limit := v_page_size;

    RETURN QUERY
    WITH total_count AS (
        SELECT COUNT(DISTINCT v.id) AS total
        FROM vacancies v
        LEFT JOIN vacancy_categories vc ON v.id = vc.vacancy_id
        LEFT JOIN vacancy_locations vl ON v.id = vl.vacancy_id
        WHERE (v_category_ids IS NULL OR vc.designer_category_id = ANY(v_category_ids))
          AND (v_location_ids IS NULL OR vl.location_id = ANY(v_location_ids))
    )
    SELECT
        v.id AS vacancy_id,
        v.title::TEXT,
        v.description::TEXT,
        v.application_url::TEXT,
        v.is_active,
        jsonb_build_object(
            'id', u.id,
            'first_name', u.first_name,
            'last_name', u.last_name,
            'email', u.email,
            'phone', u.phone,
            'profile_picture', u.profile_picture
        ) AS created_by,
        v.created_at,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id', dc.id, 'name', dc.name)) FILTER (WHERE dc.id IS NOT NULL), '[]'::jsonb) AS categories,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id', l.id, 'name', l.name)) FILTER (WHERE l.id IS NOT NULL), '[]'::jsonb) AS locations,
        tc.total::INT
    FROM
        vacancies v
    LEFT JOIN
        users u ON v.created_by = u.id
    LEFT JOIN
        vacancy_categories vc ON v.id = vc.vacancy_id
    LEFT JOIN
        designer_categories dc ON vc.designer_category_id = dc.id
    LEFT JOIN
        vacancy_locations vl ON v.id = vl.vacancy_id
    LEFT JOIN
        locations l ON vl.location_id = l.id
    CROSS JOIN
        total_count tc
    WHERE
        (v_category_ids IS NULL OR vc.designer_category_id = ANY(v_category_ids))
        AND (v_location_ids IS NULL OR vl.location_id = ANY(v_location_ids))
    GROUP BY
        v.id, tc.total, u.id
    ORDER BY
        v.created_at DESC
    LIMIT v_limit OFFSET v_offset;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION get_vacancy_by_id_with_user(
    p_vacancy_id UUID,
	p_user_id UUID
)
RETURNS TABLE (
    vacancy_id UUID,
    title TEXT,
    description TEXT,
    application_url TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    created_by JSONB,
    categories JSONB,
    locations JSONB,
	applied BOOLEAN,
	resume_url TEXT,
	resume_id UUID
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.id AS vacancy_id,
        v.title::TEXT,
        v.description::TEXT,
        v.application_url::TEXT,
        v.is_active,
        v.created_at,
        jsonb_build_object(
            'id', v.created_by,
            'first_name', u.first_name,
            'last_name', u.last_name,
            'email', u.email,
            'phone', u.phone,
            'profile_picture', u.profile_picture
        ) AS created_by,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', dc.id,
            'name', dc.name
        )) FILTER (WHERE vc.designer_category_id IS NOT NULL), '[]'::jsonb) AS categories,
        COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
            'id', l.id,
            'name', l.name
        )) FILTER (WHERE vl.location_id IS NOT NULL), '[]'::jsonb) AS locations,
		(EXISTS (SELECT 1 FROM applications a WHERE a.vacancy_id = v.id AND a.applicant_id = p_user_id)) AS applied,
		(SELECT a.resume_url FROM applications a WHERE a.vacancy_id = v.id AND a.applicant_id = p_user_id LIMIT 1) AS resume_url,
	(SELECT a.id FROM applications a WHERE a.vacancy_id = v.id AND a.applicant_id = p_user_id LIMIT 1) AS resume_id
    FROM
        vacancies v
    JOIN
        users u ON v.created_by = u.id
    LEFT JOIN
        vacancy_categories vc ON v.id = vc.vacancy_id
    LEFT JOIN
        designer_categories dc ON vc.designer_category_id = dc.id
    LEFT JOIN
        vacancy_locations vl ON v.id = vl.vacancy_id
    LEFT JOIN
        locations l ON vl.location_id = l.id
    WHERE
        v.id = p_vacancy_id
    GROUP BY
        v.id, u.id;
END;
$$ LANGUAGE plpgsql;