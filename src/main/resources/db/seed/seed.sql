-- =========================================================
-- seed.sql: Geliştirme ve performans testi için sahte veri
-- Migration DEĞİL. Elle çalıştırılır; tekrar tekrar çalıştırılabilir.
-- Sabit verilere (roller, kategoriler, renkler, konumlar) dokunmaz.
-- =========================================================

-- Toplu yüklemede otomatik eşleştirmeyi kapat (V5 trigger'ı bunu kontrol eder)
SET app.skip_matching = 'on';

-- 0) Önceki test verisini temizle
TRUNCATE report_status_history, notifications, handovers, claims, matches,
         found_reports, lost_reports, item_photos, items, users
RESTART IDENTITY CASCADE;

-- 1) Kullanıcılar: 300 normal kullanıcı
INSERT INTO users (role_id, first_name, last_name, email, password_hash, phone)
SELECT
    r.role_id,
    (ARRAY['Ayşe','Mehmet','Zeynep','Ahmet','Elif','Mustafa',
           'Fatma','Emre','Selin','Can','Deniz','Burak'])[1 + floor(random() * 12)::int],
    (ARRAY['Yılmaz','Kaya','Demir','Şahin','Çelik',
           'Yıldız','Aydın','Öztürk','Arslan','Doğan'])[1 + floor(random() * 10)::int],
    'kullanici' || g || '@ornek.com',
    'SEED_NO_LOGIN',                       -- gerçek BCrypt hash'i backend üretecek
    '05' || lpad(floor(random() * 1000000000)::bigint::text, 9, '0')
FROM generate_series(1, 300) AS g
CROSS JOIN roles r
WHERE r.code = 'USER';

-- 5 personel (İstanbul Havalimanı)
INSERT INTO users (role_id, organization_id, first_name, last_name, email, password_hash)
SELECT r.role_id, o.organization_id, 'Personel', g::text,
       'personel' || g || '@ornek.com', 'SEED_NO_LOGIN'
FROM generate_series(1, 5) AS g
CROSS JOIN roles r
CROSS JOIN organizations o
WHERE r.code = 'STAFF' AND o.name = 'İstanbul Havalimanı';

-- 1 yönetici
INSERT INTO users (role_id, first_name, last_name, email, password_hash)
SELECT role_id, 'Sistem', 'Yöneticisi', 'admin@ornek.com', 'SEED_NO_LOGIN'
FROM roles WHERE code = 'ADMIN';

-- 2) Eşyalar: 1-5000 kayıp, 5001-10000 bulunan
WITH cats AS (
    SELECT array_agg(category_id) AS ids
    FROM categories
    WHERE parent_category_id IS NOT NULL          -- sadece alt kategoriler
),
cols AS (
    SELECT array_agg(color_id) AS ids FROM colors
),
picks AS (
    SELECT
        g,
        CASE WHEN g <= 5000 THEN 'LOST' ELSE 'FOUND' END AS kind,
        cats.ids[1 + floor(random() * cardinality(cats.ids))::int] AS category_id,
        CASE WHEN random() < 0.1 THEN NULL         -- %10 renk bilinmiyor
             ELSE cols.ids[1 + floor(random() * cardinality(cols.ids))::int]
        END AS color_id,
        CASE WHEN random() < 0.2 THEN NULL         -- %20 marka bilinmiyor
             ELSE (ARRAY['Samsung','Apple','Xiaomi','Huawei','Lenovo','HP',
                         'Sony','JBL','Nike','Adidas','Zara','Casio'])[1 + floor(random() * 12)::int]
        END AS brand
    FROM generate_series(1, 10000) AS g
    CROSS JOIN cats
    CROSS JOIN cols
)
INSERT INTO items (kind, category_id, color_id, brand, title, description, secret_details)
SELECT
    p.kind,
    p.category_id,
    p.color_id,
    p.brand,
    c.name || coalesce(' - ' || col.name, ''),     -- örn. "Telefon - Siyah"
    'Test kaydı #' || p.g,
    'Gizli detay #' || p.g
FROM picks p
JOIN categories c    ON c.category_id = p.category_id
LEFT JOIN colors col ON col.color_id  = p.color_id
ORDER BY p.g;

-- 3) Kayıp bildirimleri: son 180 gün içinde, 0-6 saatlik kayıp aralığı
WITH usr AS (
    SELECT array_agg(u.user_id) AS ids
    FROM users u JOIN roles r ON r.role_id = u.role_id
    WHERE r.code = 'USER'
),
loc AS (
    SELECT array_agg(location_id) AS ids
    FROM locations
    WHERE name <> 'Kayıp Eşya Ofisi'
),
base AS (
    SELECT
        i.item_id,
        usr.ids[1 + floor(random() * cardinality(usr.ids))::int] AS user_id,
        loc.ids[1 + floor(random() * cardinality(loc.ids))::int] AS location_id,
        now() - random() * INTERVAL '180 days'                   AS t_to,
        random() * INTERVAL '6 hours'                            AS span,
        random() * INTERVAL '1 day'                              AS delay,
        random()                                                 AS r_status
    FROM items i
    CROSS JOIN usr
    CROSS JOIN loc
    WHERE i.kind = 'LOST'
)
INSERT INTO lost_reports (item_id, user_id, location_id, lost_from, lost_to,
                          status, created_at, updated_at)
SELECT
    item_id, user_id, location_id,
    t_to - span,
    t_to,
    CASE WHEN r_status < 0.85 THEN 'OPEN'
         WHEN r_status < 0.93 THEN 'CANCELLED'
         ELSE 'EXPIRED' END,
    least(now(), t_to + delay),
    least(now(), t_to + delay)
FROM base;

-- 4) Bulunan eşya bildirimleri: personel kaydeder, Kayıp Eşya Ofisi'nde saklanır
WITH stf AS (
    SELECT array_agg(u.user_id) AS ids
    FROM users u JOIN roles r ON r.role_id = u.role_id
    WHERE r.code = 'STAFF'
),
loc AS (
    SELECT array_agg(location_id) AS ids
    FROM locations
    WHERE name <> 'Kayıp Eşya Ofisi'
),
ofis AS (
    SELECT location_id FROM locations WHERE name = 'Kayıp Eşya Ofisi'
),
base AS (
    SELECT
        i.item_id,
        stf.ids[1 + floor(random() * cardinality(stf.ids))::int] AS finder_user_id,
        loc.ids[1 + floor(random() * cardinality(loc.ids))::int] AS location_id,
        now() - random() * INTERVAL '180 days'                   AS t_found,
        random() * INTERVAL '12 hours'                           AS delay,
        random()                                                 AS r_status
    FROM items i
    CROSS JOIN stf
    CROSS JOIN loc
    WHERE i.kind = 'FOUND'
)
INSERT INTO found_reports (item_id, finder_user_id, location_id, storage_location_id,
                           found_at, status, created_at, updated_at)
SELECT
    b.item_id, b.finder_user_id, b.location_id, ofis.location_id,
    b.t_found,
    CASE WHEN b.r_status < 0.9 THEN 'IN_STORAGE' ELSE 'DISPOSED' END,
    least(now(), b.t_found + b.delay),
    least(now(), b.t_found + b.delay)
FROM base b
CROSS JOIN ofis;

-- Otomatik eşleştirmeyi tekrar aç
RESET app.skip_matching;