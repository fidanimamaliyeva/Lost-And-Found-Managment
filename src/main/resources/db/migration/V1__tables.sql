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