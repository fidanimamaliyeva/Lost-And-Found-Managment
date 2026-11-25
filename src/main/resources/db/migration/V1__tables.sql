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


-- =========================================================
-- Bölüm 3: Eşyalar ve bildirimler
-- =========================================================

-- Eşyanın özellikleri (kayıp ve bulunan kayıtlar için ortak)
CREATE TABLE items (
    item_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind            VARCHAR(5)   NOT NULL,          -- 'LOST' ya da 'FOUND'
    category_id     INTEGER      NOT NULL,
    color_id        INTEGER,                        -- NULL = renk bilinmiyor
    brand           VARCHAR(60),                    -- NULL = marka bilinmiyor
    title           VARCHAR(120) NOT NULL,          -- örn. "Siyah Samsung telefon"
    description     TEXT,                           -- herkese açık açıklama
    secret_details  TEXT,                           -- sadece personelin göreceği gizli detay
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT fk_items_category
        FOREIGN KEY (category_id) REFERENCES categories (category_id),
    CONSTRAINT fk_items_color
        FOREIGN KEY (color_id) REFERENCES colors (color_id),
    CONSTRAINT uq_items_id_kind UNIQUE (item_id, kind),   -- bileşik FK hedefi
    CONSTRAINT chk_items_kind   CHECK (kind IN ('LOST', 'FOUND')),
    CONSTRAINT chk_items_title  CHECK (btrim(title) <> ''),
    CONSTRAINT chk_items_brand  CHECK (brand IS NULL OR btrim(brand) <> '')
);

-- Eşya fotoğrafları (dosya diskte, burada sadece yolu)
CREATE TABLE item_photos (
    photo_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id      BIGINT       NOT NULL,
    file_path    VARCHAR(300) NOT NULL,
    uploaded_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT fk_item_photos_item
        FOREIGN KEY (item_id) REFERENCES items (item_id) ON DELETE CASCADE,
    CONSTRAINT uq_item_photos_path UNIQUE (file_path),
    CONSTRAINT chk_item_photos_ext CHECK (file_path ~* '\.(jpg|jpeg|png)$')
);

-- Kayıp bildirimleri
CREATE TABLE lost_reports (
    lost_report_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id         BIGINT      NOT NULL,
    item_kind       VARCHAR(5)  NOT NULL DEFAULT 'LOST',
    user_id         BIGINT      NOT NULL,
    location_id     INTEGER     NOT NULL,
    lost_from       TIMESTAMPTZ NOT NULL,   -- "en erken şu saatte kaybolmuş olabilir"
    lost_to         TIMESTAMPTZ NOT NULL,   -- "en geç şu saatte fark ettim"
    status          VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_lost_reports_item UNIQUE (item_id),              -- 1 eşya = 1 bildirim
    CONSTRAINT chk_lost_reports_item_kind CHECK (item_kind = 'LOST'),
    CONSTRAINT fk_lost_reports_item_kind
        FOREIGN KEY (item_id, item_kind) REFERENCES items (item_id, kind),
    CONSTRAINT fk_lost_reports_user
        FOREIGN KEY (user_id) REFERENCES users (user_id),
    CONSTRAINT fk_lost_reports_location
        FOREIGN KEY (location_id) REFERENCES locations (location_id),
    CONSTRAINT chk_lost_reports_range
        CHECK (lost_from <= lost_to),
    CONSTRAINT chk_lost_reports_max_range
        CHECK (lost_to - lost_from <= INTERVAL '30 days'),
    CONSTRAINT chk_lost_reports_not_future            -- 5 dk saat farkı toleransı
        CHECK (lost_to <= created_at + INTERVAL '5 minutes'),
    CONSTRAINT chk_lost_reports_status
        CHECK (status IN ('OPEN', 'RESOLVED', 'CANCELLED', 'EXPIRED'))
);

-- Bulunan eşya bildirimleri
CREATE TABLE found_reports (
    found_report_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id              BIGINT      NOT NULL,
    item_kind            VARCHAR(5)  NOT NULL DEFAULT 'FOUND',
    finder_user_id       BIGINT      NOT NULL,
    location_id          INTEGER     NOT NULL,   -- bulunduğu yer
    storage_location_id  INTEGER,                -- emanette durduğu yer
    found_at             TIMESTAMPTZ NOT NULL,
    status               VARCHAR(20) NOT NULL DEFAULT 'IN_STORAGE',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_found_reports_item UNIQUE (item_id),
    CONSTRAINT chk_found_reports_item_kind CHECK (item_kind = 'FOUND'),
    CONSTRAINT fk_found_reports_item_kind
        FOREIGN KEY (item_id, item_kind) REFERENCES items (item_id, kind),
    CONSTRAINT fk_found_reports_finder
        FOREIGN KEY (finder_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_found_reports_location
        FOREIGN KEY (location_id) REFERENCES locations (location_id),
    CONSTRAINT fk_found_reports_storage
        FOREIGN KEY (storage_location_id) REFERENCES locations (location_id),
    CONSTRAINT chk_found_reports_not_future
        CHECK (found_at <= created_at + INTERVAL '5 minutes'),
    CONSTRAINT chk_found_reports_status
        CHECK (status IN ('IN_STORAGE', 'CLAIM_PENDING', 'HANDED_OVER', 'DISPOSED'))
);

-- =========================================================
-- Bölüm 4: Eşleşme, talep, teslim, bildirim, durum geçmişi
-- =========================================================

-- Sistemin bulduğu eşleşmeler (lost_reports N-N found_reports ara tablosu)
CREATE TABLE matches (
    match_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lost_report_id   BIGINT        NOT NULL,
    found_report_id  BIGINT        NOT NULL,
    score            NUMERIC(5, 2) NOT NULL,
    score_detail     JSONB         NOT NULL DEFAULT '{}'::jsonb,
    status           VARCHAR(20)   NOT NULL DEFAULT 'SUGGESTED',
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT fk_matches_lost
        FOREIGN KEY (lost_report_id) REFERENCES lost_reports (lost_report_id),
    CONSTRAINT fk_matches_found
        FOREIGN KEY (found_report_id) REFERENCES found_reports (found_report_id),
    CONSTRAINT uq_matches_pair UNIQUE (lost_report_id, found_report_id),
    CONSTRAINT uq_matches_id_found UNIQUE (match_id, found_report_id),  -- bileşik FK hedefi
    CONSTRAINT chk_matches_score  CHECK (score BETWEEN 0 AND 100),
    CONSTRAINT chk_matches_detail CHECK (jsonb_typeof(score_detail) = 'object'),
    CONSTRAINT chk_matches_status CHECK (status IN ('SUGGESTED', 'CONFIRMED', 'DISMISSED'))
);

-- Sahiplenme talepleri
CREATE TABLE claims (
    claim_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    found_report_id   BIGINT      NOT NULL,
    claimant_user_id  BIGINT      NOT NULL,
    lost_report_id    BIGINT,                  -- kullanıcının kendi kayıp bildirimi (varsa)
    match_id          BIGINT,                  -- talep bir eşleşmeden geldiyse
    proof_text        TEXT        NOT NULL,    -- sahiplik kanıtı / gizli detay cevabı
    status            VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    reviewed_by       BIGINT,                  -- talebi inceleyen personel
    reviewed_at       TIMESTAMPTZ,
    reject_reason     TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_claims_found
        FOREIGN KEY (found_report_id) REFERENCES found_reports (found_report_id),
    CONSTRAINT fk_claims_claimant
        FOREIGN KEY (claimant_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_claims_lost
        FOREIGN KEY (lost_report_id) REFERENCES lost_reports (lost_report_id),
    -- Eşleşme verildiyse aynı bulunan eşyaya ait olmalı
    CONSTRAINT fk_claims_match_same_found
        FOREIGN KEY (match_id, found_report_id) REFERENCES matches (match_id, found_report_id),
    CONSTRAINT fk_claims_reviewer
        FOREIGN KEY (reviewed_by) REFERENCES users (user_id),

    CONSTRAINT uq_claims_one_per_user UNIQUE (found_report_id, claimant_user_id),
    CONSTRAINT chk_claims_status
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT chk_claims_proof
        CHECK (length(btrim(proof_text)) >= 10),
    -- İnceleyen ve inceleme zamanı ya ikisi birden dolu ya ikisi birden boş
    CONSTRAINT chk_claims_review_pair
        CHECK ((reviewed_by IS NULL) = (reviewed_at IS NULL)),
    -- Onaylanan/reddedilen talep incelenmiş olmalı; bekleyen/iptal olan incelenmemiş
    CONSTRAINT chk_claims_reviewed
        CHECK ((status IN ('APPROVED', 'REJECTED')) = (reviewed_by IS NOT NULL)),
    CONSTRAINT chk_claims_reject_reason
        CHECK (status <> 'REJECTED' OR btrim(coalesce(reject_reason, '')) <> ''),
    CONSTRAINT chk_claims_not_self_review
        CHECK (reviewed_by IS NULL OR reviewed_by <> claimant_user_id)
);

-- Bir eşya için en fazla bir onaylı talep
CREATE UNIQUE INDEX uq_claims_one_approved
    ON claims (found_report_id)
    WHERE status = 'APPROVED';

-- Teslim kayıtları (onaylı talep başına en fazla bir teslim)
CREATE TABLE handovers (
    handover_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_id             BIGINT      NOT NULL,
    staff_user_id        BIGINT      NOT NULL,
    handed_over_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    verification_method  VARCHAR(30) NOT NULL,
    notes                TEXT,

    CONSTRAINT fk_handovers_claim
        FOREIGN KEY (claim_id) REFERENCES claims (claim_id),
    CONSTRAINT fk_handovers_staff
        FOREIGN KEY (staff_user_id) REFERENCES users (user_id),
    CONSTRAINT uq_handovers_claim UNIQUE (claim_id),
    CONSTRAINT chk_handovers_method
        CHECK (verification_method IN ('ID_CARD', 'PROOF_OF_PURCHASE', 'SECRET_DETAILS', 'OTHER'))
);

-- Kullanıcı bildirimleri
CREATE TABLE notifications (
    notification_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT      NOT NULL,
    type             VARCHAR(30) NOT NULL,
    match_id         BIGINT,
    claim_id         BIGINT,
    message          TEXT        NOT NULL,
    is_read          BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_notifications_user
        FOREIGN KEY (user_id) REFERENCES users (user_id),
    CONSTRAINT fk_notifications_match
        FOREIGN KEY (match_id) REFERENCES matches (match_id),
    CONSTRAINT fk_notifications_claim
        FOREIGN KEY (claim_id) REFERENCES claims (claim_id),
    CONSTRAINT chk_notifications_type
        CHECK (type IN ('MATCH_FOUND', 'CLAIM_APPROVED', 'CLAIM_REJECTED', 'READY_FOR_PICKUP')),
    -- Bildirim türü, ilgili kaydı göstermeli
    CONSTRAINT chk_notifications_reference
        CHECK (
            (type = 'MATCH_FOUND' AND match_id IS NOT NULL)
            OR (type IN ('CLAIM_APPROVED', 'CLAIM_REJECTED', 'READY_FOR_PICKUP') AND claim_id IS NOT NULL)
        )
);

-- Bildirimlerin durum geçmişi (6. aşamada trigger dolduracak)
CREATE TABLE report_status_history (
    history_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lost_report_id   BIGINT,
    found_report_id  BIGINT,
    old_status       VARCHAR(20),              -- NULL = kayıt yeni oluşturuldu
    new_status       VARCHAR(20) NOT NULL,
    changed_by       BIGINT,
    changed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_history_lost
        FOREIGN KEY (lost_report_id) REFERENCES lost_reports (lost_report_id),
    CONSTRAINT fk_history_found
        FOREIGN KEY (found_report_id) REFERENCES found_reports (found_report_id),
    CONSTRAINT fk_history_changed_by
        FOREIGN KEY (changed_by) REFERENCES users (user_id),
    CONSTRAINT chk_history_one_report
        CHECK (num_nonnulls(lost_report_id, found_report_id) = 1),
    CONSTRAINT chk_history_changed
        CHECK (old_status IS DISTINCT FROM new_status)
);