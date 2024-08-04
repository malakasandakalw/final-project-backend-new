-- CREATE DATABASE designer_digest_db;
-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE
    user_roles (
        id UUID DEFAULT uuid_generate_v4 () NOT NULL,
        key VARCHAR(10) NOT NULL,
        value VARCHAR(10) NOT NULL
    );

ALTER TABLE user_roles ADD CONSTRAINT user_roles_pk PRIMARY KEY (id);

INSERT INTO
    user_roles (key, value)
VALUES
    ('DESIGNER', 'Designer'),
    ('EMPLOYER', 'Employer'),
    ('PERSONAL', 'Personal');

CREATE TABLE
    users (
        id UUID DEFAULT uuid_generate_v4 () NOT NULL,
        first_name VARCHAR(30) NOT NULL,
        last_name VARCHAR(30) NOT NULL,
        email VARCHAR(30) NOT NULL UNIQUE,
        password TEXT NOT NULL,
        is_verified BOOLEAN DEFAULT FALSE,
        user_role UUID NOT NULL,
        created_at TIMESTAMP
        WITH
            TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
    );

ALTER TABLE users ADD CONSTRAINT users_pk PRIMARY KEY (id);

ALTER TABLE users ADD CONSTRAINT users_user_role_fk FOREIGN KEY (user_role) REFERENCES user_roles;

CREATE TABLE
    categories (
        id UUID DEFAULT uuid_generate_v4 () NOT NULL,
        name VARCHAR(50) NOT NULL
    );

ALTER TABLE categories ADD CONSTRAINT categories_pk PRIMARY KEY (id);

INSERT INTO categories(name) VALUES ('Apparel'), ('Ready-to-wear'), ('Mass market'), ('Footwear'), ('Accessory'), ('Sportwear'), ('Evening wear'), ('Childrenswear'), ('Classic wear'), ('Eco friendly');

CREATE TABLE
    posts (
        id UUID DEFAULT uuid_generate_v4 () NOT NULL,
        title TEXT NOT NULL,
        type VARCHAR(10) NOT NULL,
        media_url TEXT NOT NULL,
        upvotes INTEGER DEFAULT(0),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
        
        user_id UUID NOT NULL
    );

ALTER TABLE posts ADD CONSTRAINT posts_pk PRIMARY KEY (id);
ALTER TABLE posts ADD CONSTRAINT post_user_id_fk FOREIGN KEY (user_id) REFERENCES users;

CREATE TABLE post_categories(
	post_id UUID NOT NULL,
	category_id UUID NOT NULL
);
ALTER TABLE post_categories ADD CONSTRAINT post_categories_post_id_fk FOREIGN KEY (post_id) REFERENCES posts;
ALTER TABLE post_categories ADD CONSTRAINT post_categories_category_id_fk FOREIGN KEY (category_id) REFERENCES categories;


-- designer categorie
CREATE TABLE
    designer_categories (
        id UUID DEFAULT uuid_generate_v4 () NOT NULL,
        name VARCHAR(50) NOT NULL
    );

ALTER TABLE designer_categories ADD CONSTRAINT designer_categories_pk PRIMARY KEY (id);

INSERT INTO designer_categories(name) VALUES ('Apparel Designer'), ('Costume Designer'), ('Accessories Designer'), ('Footwear Designer'), ('Economy Fashion Designer');

-- locations
CREATE TABLE locations(
        id UUID DEFAULT uuid_generate_v4 () NOT NULL,
        name VARCHAR(20) NOT NULL
);

ALTER TABLE locations ADD CONSTRAINT locations_pk PRIMARY KEY (id);

INSERT INTO locations(name) VALUES 
('Ampara'), 
('Anuradhapura'), 
('Badulla'), 
('Batticaloa'), 
('Colombo'), 
('Galle'), 
('Gampaha'), 
('Hambantota'), 
('Jaffna'), 
('Kalutara'), 
('Kandy'),
('Kegalle'),
('Kilinochchi'),
('Kurunegala'),
('Mannar'),
('Matale'),
('Matara'),
('Monaragala'),
('Mullaitivu'),
('NuwaraEliya'),
('Polonnaruwa'),
('Puttalam'),
('Ratnapura'),
('Trincomalee'),
('Vavuniya');