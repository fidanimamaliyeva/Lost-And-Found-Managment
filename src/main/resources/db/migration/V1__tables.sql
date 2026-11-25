-- =========================================================
-- V1: Tablolar ve kısıtlar
-- Bölüm 1: Bağımsız (lookup) tablolar
-- =========================================================


-- Kullanıcı rolleri: normal kullanıcı, kurum personeli, yönetici
CREATE TABLE roles (
    role_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code     VARCHAR(20) NOT NULL,
    CONSTRAINT uq_roles_code  UNIQUE (code),
    CONSTRAINT chk_roles_code CHECK (code IN ('USER', 'STAFF', 'ADMIN'))
);

-- Sistemi kullanan kurumlar: havalimanı, üniversite..
CREATE TABLE organizations (
    organization_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name             VARCHAR(150) NOT NULL,
    org_type         VARCHAR(20)  NOT NULL,
    city             VARCHAR(80)  NOT NULL,
    phone            VARCHAR(20),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_organizations_name UNIQUE (name),
    CONSTRAINT chk_organizations_type
        CHECK (org_type IN ('AIRPORT', 'UNIVERSITY', 'MALL', 'TRANSPORT', 'OTHER'))
);

-- Sabit renk listesi (serbest metin yerine; eşleştirme için önemli)
CREATE TABLE colors (
    color_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name      VARCHAR(30) NOT NULL,
    CONSTRAINT uq_colors_name UNIQUE (name)
);

-- Kategoriler: kendi kendine bağlı (Elektronik -> Telefon)
CREATE TABLE categories (
    category_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_category_id  INTEGER,
    name                VARCHAR(80) NOT NULL,
    CONSTRAINT fk_categories_parent
        FOREIGN KEY (parent_category_id) REFERENCES categories (category_id),
    CONSTRAINT uq_categories_parent_name
        UNIQUE NULLS NOT DISTINCT (parent_category_id, name),
    CONSTRAINT chk_categories_not_self
        CHECK (parent_category_id IS NULL OR parent_category_id <> category_id)
);



-- =========================================================
-- Bölüm 2: Konumlar ve kullanıcılar
-- =========================================================

-- Konumlar: iç içe (İstanbul Havalimanı -> Terminal 1 -> Kapı A3)
CREATE TABLE locations (
    location_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id     INTEGER      NOT NULL,
    parent_location_id  INTEGER,
    name                VARCHAR(120) NOT NULL,
    location_type       VARCHAR(20)  NOT NULL,
    latitude            NUMERIC(9, 6),
    longitude           NUMERIC(9, 6),

    CONSTRAINT fk_locations_organization
        FOREIGN KEY (organization_id) REFERENCES organizations (organization_id),

    -- Bileşik FK'nin hedef alabilmesi için (konum, kurum) çifti tekil olmalı
    CONSTRAINT uq_locations_id_org UNIQUE (location_id, organization_id),

    -- Üst konum aynı kurumdan olmalı
    CONSTRAINT fk_locations_parent_same_org
        FOREIGN KEY (parent_location_id, organization_id)
        REFERENCES locations (location_id, organization_id),

    CONSTRAINT uq_locations_org_parent_name
        UNIQUE NULLS NOT DISTINCT (organization_id, parent_location_id, name),
    CONSTRAINT chk_locations_type
        CHECK (location_type IN ('CAMPUS', 'BUILDING', 'TERMINAL', 'FLOOR',
                                 'AREA', 'GATE', 'STATION', 'OTHER')),
    CONSTRAINT chk_locations_lat  CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT chk_locations_lng  CHECK (longitude BETWEEN -180 AND 180),
    -- Koordinat ya ikisi birden girilir ya hiç girilmez
    CONSTRAINT chk_locations_coords_pair
        CHECK ((latitude IS NULL) = (longitude IS NULL)),
    CONSTRAINT chk_locations_not_self
        CHECK (parent_location_id IS NULL OR parent_location_id <> location_id)
);

-- Kullanıcılar
CREATE TABLE users (
    user_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id          INTEGER      NOT NULL,
    organization_id  INTEGER,                 -- sadece STAFF için dolu (V3'te trigger ile kontrol)
    first_name       VARCHAR(60)  NOT NULL,
    last_name        VARCHAR(60)  NOT NULL,
    email            VARCHAR(255) NOT NULL,
    password_hash    VARCHAR(100) NOT NULL,   -- BCrypt hash'i, asla düz şifre değil
    phone            VARCHAR(20),
    is_active        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT fk_users_role
        FOREIGN KEY (role_id) REFERENCES roles (role_id),
    CONSTRAINT fk_users_organization
        FOREIGN KEY (organization_id) REFERENCES organizations (organization_id),
    CONSTRAINT chk_users_email
        CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CONSTRAINT chk_users_names
        CHECK (btrim(first_name) <> '' AND btrim(last_name) <> '')
);

-- Büyük/küçük harf farkı gözetmeden e-posta tekilliği
CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email));