-- =========================================================
-- V4: Konum yolu fonksiyonu ve herkese açık bulunan eşya listesi
-- =========================================================

-- Bir konumun tam yolunu döndürür:
-- location_path(<Biniş Kapıları id>) -> 'Dış Hatlar Terminali > Gidiş Katı > Biniş Kapıları'
CREATE OR REPLACE FUNCTION location_path(p_location_id INTEGER)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE path AS (
        -- Başlangıç: verilen konum
        SELECT location_id, parent_location_id, name, 1 AS depth
        FROM locations
        WHERE location_id = p_location_id

        UNION ALL

        -- Tekrar eden kısım: bir önceki satırın üst konumu
        SELECT l.location_id, l.parent_location_id, l.name, p.depth + 1
        FROM locations l
        JOIN path p ON l.location_id = p.parent_location_id
    )
    SELECT string_agg(name, ' > ' ORDER BY depth DESC)
    FROM path;
$$;

-- Herkese açık bulunan eşya listesi
-- GÖSTERİLMEYENLER: secret_details, bulan kişi, saklama yeri, tam saat
CREATE OR REPLACE VIEW v_public_found_items AS
SELECT
    f.found_report_id,
    i.title,
    i.description,
    pc.name                       AS parent_category,
    c.name                        AS category,
    col.name                      AS color,
    i.brand,
    location_path(f.location_id)  AS found_location,
    f.found_at::date              AS found_date,      -- sadece gün; saat gizli
    f.status
FROM found_reports f
JOIN items i            ON i.item_id      = f.item_id
JOIN categories c       ON c.category_id  = i.category_id
LEFT JOIN categories pc ON pc.category_id = c.parent_category_id
LEFT JOIN colors col    ON col.color_id   = i.color_id
WHERE f.status IN ('IN_STORAGE', 'CLAIM_PENDING');   -- teslim edilmiş/imha edilmişler listede yok