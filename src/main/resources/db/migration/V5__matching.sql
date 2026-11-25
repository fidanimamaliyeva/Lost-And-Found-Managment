-- =========================================================
-- V5: Eşleştirme sistemi
-- =========================================================

-- ---------------------------------------------------------
-- Yardımcı 1: Bir konumun kökten kendisine kadar ID yolu
-- location_ancestry(<Biniş Kapıları>) -> {Dış Hatlar Terminali, Gidiş Katı, Biniş Kapıları}
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION location_ancestry(p_location_id INTEGER)
RETURNS INTEGER[]
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE path AS (
        SELECT location_id, parent_location_id, 1 AS depth
        FROM locations
        WHERE location_id = p_location_id

        UNION ALL

        SELECT l.location_id, l.parent_location_id, p.depth + 1
        FROM locations l
        JOIN path p ON l.location_id = p.parent_location_id
    )
    SELECT array_agg(location_id ORDER BY depth DESC)
    FROM path;
$$;

-- ---------------------------------------------------------
-- Yardımcı 2: İki metindeki ortak kelime oranı (0-10 puan)
-- En az 3 harfli kelimeler; ortak kelime / kısa metnin kelime sayısı
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION text_similarity_score(p_a TEXT, p_b TEXT)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    WITH wa AS (
        SELECT DISTINCT w
        FROM regexp_split_to_table(lower(coalesce(p_a, '')), '[[:space:][:punct:]]+') AS w
        WHERE length(w) >= 3
    ),
    wb AS (
        SELECT DISTINCT w
        FROM regexp_split_to_table(lower(coalesce(p_b, '')), '[[:space:][:punct:]]+') AS w
        WHERE length(w) >= 3
    ),
    counts AS (
        SELECT (SELECT count(*) FROM wa)                   AS na,
               (SELECT count(*) FROM wb)                   AS nb,
               (SELECT count(*) FROM wa JOIN wb USING (w)) AS common
    )
    SELECT CASE WHEN least(na, nb) = 0 THEN 0
                ELSE round(10.0 * common / least(na, nb), 2)
           END
    FROM counts;
$$;

-- ---------------------------------------------------------
-- Ana fonksiyon: bir kayıp + bir bulunan bildirimi için puan ve döküm
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_match_score(
    p_lost_id   BIGINT,
    p_found_id  BIGINT,
    OUT score   NUMERIC,
    OUT detail  JSONB
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    l        RECORD;
    f        RECORD;
    l_path   INTEGER[];
    f_path   INTEGER[];
    s_cat    NUMERIC := 0;
    s_loc    NUMERIC := 0;
    s_color  NUMERIC := 0;
    s_brand  NUMERIC := 0;
    s_date   NUMERIC := 0;
    s_text   NUMERIC := 0;
BEGIN
    -- Kayıp bildiriminin bilgileri
    SELECT lr.location_id, lr.lost_from, lr.lost_to,
           i.category_id, c.parent_category_id, i.color_id, i.brand, i.title, i.description
    INTO l
    FROM lost_reports lr
    JOIN items i      ON i.item_id     = lr.item_id
    JOIN categories c ON c.category_id = i.category_id
    WHERE lr.lost_report_id = p_lost_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kayıp bildirimi bulunamadı: %', p_lost_id;
    END IF;

    -- Bulunan bildiriminin bilgileri
    SELECT fr.location_id, fr.found_at,
           i.category_id, c.parent_category_id, i.color_id, i.brand, i.title, i.description
    INTO f
    FROM found_reports fr
    JOIN items i      ON i.item_id     = fr.item_id
    JOIN categories c ON c.category_id = i.category_id
    WHERE fr.found_report_id = p_found_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bulunan bildirimi bulunamadı: %', p_found_id;
    END IF;

    -- 1) Kategori (25)
    IF l.category_id = f.category_id THEN
        s_cat := 25;
    ELSIF coalesce(l.parent_category_id, l.category_id)
        = coalesce(f.parent_category_id, f.category_id) THEN
        s_cat := 12;
    END IF;

    -- 2) Konum (20)
    l_path := location_ancestry(l.location_id);
    f_path := location_ancestry(f.location_id);

    IF l.location_id = f.location_id THEN
        s_loc := 20;
    ELSIF l.location_id = ANY (f_path) OR f.location_id = ANY (l_path) THEN
        s_loc := 16;                                       -- biri diğerinin içinde
    ELSIF cardinality(l_path) > 1 AND cardinality(f_path) > 1
      AND l_path[cardinality(l_path) - 1] = f_path[cardinality(f_path) - 1] THEN
        s_loc := 14;                                       -- aynı üst konum (kardeş)
    ELSIF l_path[1] = f_path[1] THEN
        s_loc := 8;                                        -- aynı terminal/bölüm
    END IF;

    -- 3) Renk (15)
    IF l.color_id IS NULL OR f.color_id IS NULL THEN
        s_color := 5;
    ELSIF l.color_id = f.color_id THEN
        s_color := 15;
    END IF;

    -- 4) Marka (15)
    IF l.brand IS NULL OR f.brand IS NULL THEN
        s_brand := 5;
    ELSIF lower(btrim(l.brand)) = lower(btrim(f.brand)) THEN
        s_brand := 15;
    END IF;

    -- 5) Tarih (15)
    IF f.found_at BETWEEN l.lost_from AND l.lost_to THEN
        s_date := 15;
    ELSIF f.found_at > l.lost_to THEN
        s_date := CASE
                      WHEN f.found_at - l.lost_to <= INTERVAL '1 day'  THEN 12
                      WHEN f.found_at - l.lost_to <= INTERVAL '3 days' THEN 8
                      WHEN f.found_at - l.lost_to <= INTERVAL '7 days' THEN 4
                      ELSE 0
                  END;
    ELSIF f.found_at >= l.lost_from - INTERVAL '1 day' THEN
        s_date := 6;                                       -- kullanıcı saati yanlış hatırlamış olabilir
    END IF;

    -- 6) Açıklama (10)
    s_text := text_similarity_score(concat_ws(' ', l.title, l.description),
                                    concat_ws(' ', f.title, f.description));

    score  := s_cat + s_loc + s_color + s_brand + s_date + s_text;
    detail := jsonb_build_object(
                  'kategori', s_cat,   'konum', s_loc,  'renk',     s_color,
                  'marka',    s_brand, 'tarih', s_date, 'aciklama', s_text);
END;
$$;

-- ---------------------------------------------------------
-- Eşleştirmeyi çalıştır
-- run_matching(lost_id)         -> bir kayıp bildirimi için
-- run_matching(NULL, found_id)  -> bir bulunan bildirimi için
-- run_matching()                -> tüm açık kayıtlar için (toplu, yavaş olabilir)
-- Dönüş: eklenen eşleşme sayısı
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION run_matching(
    p_lost_id    BIGINT  DEFAULT NULL,
    p_found_id   BIGINT  DEFAULT NULL,
    p_min_score  NUMERIC DEFAULT 50
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    INSERT INTO matches (lost_report_id, found_report_id, score, score_detail)
    SELECT c.lost_report_id, c.found_report_id, s.score, s.detail
    FROM (
        -- Aday filtresi: puanlanmadan elenenler burada düşer
        SELECT l.lost_report_id, f.found_report_id
        FROM lost_reports l
        JOIN items li        ON li.item_id     = l.item_id
        JOIN categories lc   ON lc.category_id = li.category_id
        JOIN locations ll    ON ll.location_id = l.location_id
        JOIN found_reports f ON f.status = 'IN_STORAGE'
                            AND f.found_at >= l.lost_from - INTERVAL '1 day'
                            AND f.found_at <= l.lost_to   + INTERVAL '30 days'
        JOIN items fi        ON fi.item_id     = f.item_id
        JOIN categories fc   ON fc.category_id = fi.category_id
        JOIN locations fl    ON fl.location_id = f.location_id
        WHERE l.status = 'OPEN'
          AND fl.organization_id = ll.organization_id
          AND coalesce(lc.parent_category_id, lc.category_id)
            = coalesce(fc.parent_category_id, fc.category_id)
          AND (p_lost_id  IS NULL OR l.lost_report_id  = p_lost_id)
          AND (p_found_id IS NULL OR f.found_report_id = p_found_id)
    ) c
    CROSS JOIN LATERAL calculate_match_score(c.lost_report_id, c.found_report_id) s
    WHERE s.score >= p_min_score
    ON CONFLICT (lost_report_id, found_report_id) DO NOTHING;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- ---------------------------------------------------------
-- Trigger: yeni kayıp/bulunan bildiriminde eşleştirmeyi çalıştır
-- Toplu veri yüklerken atlamak için: SET app.skip_matching = 'on';
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_run_matching()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF coalesce(current_setting('app.skip_matching', true), '') = 'on' THEN
        RETURN NULL;
    END IF;

    IF TG_TABLE_NAME = 'lost_reports' THEN
        PERFORM run_matching(NEW.lost_report_id, NULL);
    ELSE
        PERFORM run_matching(NULL, NEW.found_report_id);
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_lost_reports_match
    AFTER INSERT ON lost_reports
    FOR EACH ROW EXECUTE FUNCTION trg_run_matching();

CREATE TRIGGER trg_found_reports_match
    AFTER INSERT ON found_reports
    FOR EACH ROW EXECUTE FUNCTION trg_run_matching();

-- ---------------------------------------------------------
-- Trigger: yeni eşleşmede kayıp sahibine bildirim
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_notify_match()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id  BIGINT;
    v_title    TEXT;
BEGIN
    SELECT lr.user_id, i.title
    INTO v_user_id, v_title
    FROM lost_reports lr
    JOIN items i ON i.item_id = lr.item_id
    WHERE lr.lost_report_id = NEW.lost_report_id;

    INSERT INTO notifications (user_id, type, match_id, message)
    VALUES (v_user_id, 'MATCH_FOUND', NEW.match_id,
            format('"%s" için %%%s uyumlu bir bulunan eşya kaydı var.',
                   v_title, round(NEW.score)));

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_matches_notify
    AFTER INSERT ON matches
    FOR EACH ROW EXECUTE FUNCTION trg_notify_match();