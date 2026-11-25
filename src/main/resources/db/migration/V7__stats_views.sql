-- =========================================================
-- V7: Yönetici paneli istatistik görünümleri
-- =========================================================

-- Panelin üstündeki sayı kartları (tek satır)
CREATE OR REPLACE VIEW v_admin_dashboard AS
SELECT
    (SELECT count(*) FROM users u JOIN roles r ON r.role_id = u.role_id
      WHERE r.code = 'USER')                                         AS total_users,
    (SELECT count(*) FROM lost_reports)                                 AS total_lost,
    (SELECT count(*) FROM lost_reports  WHERE status = 'OPEN')          AS open_lost,
    (SELECT count(*) FROM found_reports)                                AS total_found,
    (SELECT count(*) FROM found_reports WHERE status = 'IN_STORAGE')    AS in_storage,
    (SELECT count(*) FROM matches       WHERE status = 'SUGGESTED')     AS open_matches,
    (SELECT count(*) FROM claims        WHERE status = 'PENDING')       AS pending_claims,
    (SELECT count(*) FROM handovers)                                    AS total_handovers,
    (SELECT round(avg(EXTRACT(EPOCH FROM (h.handed_over_at - f.created_at)) / 3600)::numeric, 1)
       FROM handovers h
       JOIN claims c        ON c.claim_id        = h.claim_id
       JOIN found_reports f ON f.found_report_id = c.found_report_id)   AS avg_hours_to_handover;

-- Ana kategori bazında kayıp / bulunan / teslim sayıları
CREATE OR REPLACE VIEW v_category_stats AS
SELECT
    coalesce(pc.name, c.name)                                        AS category,
    count(*) FILTER (WHERE i.kind = 'LOST')                          AS lost_count,
    count(*) FILTER (WHERE i.kind = 'FOUND')                         AS found_count,
    count(*) FILTER (WHERE f.status = 'HANDED_OVER')                 AS handed_over_count,
    round(100.0 * count(*) FILTER (WHERE f.status = 'HANDED_OVER')
          / nullif(count(*) FILTER (WHERE i.kind = 'FOUND'), 0), 1)  AS return_rate_pct
FROM items i
JOIN categories c        ON c.category_id  = i.category_id
LEFT JOIN categories pc  ON pc.category_id = c.parent_category_id
LEFT JOIN found_reports f ON f.item_id     = i.item_id
GROUP BY coalesce(pc.name, c.name);

-- Konum bazında yoğunluk: en çok eşya kaybedilen yerler
CREATE OR REPLACE VIEW v_location_hotspots AS
WITH lost_counts AS (
    SELECT location_id, count(*) AS lost_count
    FROM lost_reports
    GROUP BY location_id
),
found_counts AS (
    SELECT location_id, count(*) AS found_count
    FROM found_reports
    GROUP BY location_id
)
SELECT
    l.location_id,
    location_path(l.location_id)                                     AS location,
    coalesce(lc.lost_count, 0)                                       AS lost_count,
    coalesce(fc.found_count, 0)                                      AS found_count,
    RANK() OVER (ORDER BY coalesce(lc.lost_count, 0) DESC)           AS lost_rank
FROM locations l
LEFT JOIN lost_counts  lc ON lc.location_id = l.location_id
LEFT JOIN found_counts fc ON fc.location_id = l.location_id;

-- Son 12 ay: aylık kayıp / bulunan / teslim (kayıt olmayan aylar 0)
CREATE OR REPLACE VIEW v_monthly_stats AS
WITH months AS (
    SELECT generate_series(date_trunc('month', now()) - INTERVAL '11 months',
                           date_trunc('month', now()),
                           INTERVAL '1 month') AS month_start
)
SELECT
    to_char(m.month_start, 'YYYY-MM') AS month,
    (SELECT count(*) FROM lost_reports
      WHERE created_at >= m.month_start
        AND created_at <  m.month_start + INTERVAL '1 month') AS lost_count,
    (SELECT count(*) FROM found_reports
      WHERE created_at >= m.month_start
        AND created_at <  m.month_start + INTERVAL '1 month') AS found_count,
    (SELECT count(*) FROM handovers
      WHERE handed_over_at >= m.month_start
        AND handed_over_at <  m.month_start + INTERVAL '1 month') AS handover_count
FROM months m;

-- Her kayıp bildirimi için eşleşmelerin sırası ve seviyesi (kullanıcı paneli için)
CREATE OR REPLACE VIEW v_match_rankings AS
SELECT
    m.match_id,
    m.lost_report_id,
    m.found_report_id,
    m.score,
    m.score_detail,
    m.status,
    m.created_at,
    RANK() OVER (PARTITION BY m.lost_report_id ORDER BY m.score DESC) AS rank_for_lost,
    CASE WHEN m.score >= 80 THEN 'HIGH'
         WHEN m.score >= 60 THEN 'MEDIUM'
         ELSE 'LOW' END                                               AS level
FROM matches m
WHERE m.status <> 'DISMISSED';