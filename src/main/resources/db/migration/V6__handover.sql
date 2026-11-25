-- =========================================================
-- V6: Sahiplenme talebi ve teslim süreci
-- =========================================================

-- ---------------------------------------------------------
-- Yetki kontrolü: bu kullanıcı bu bulunan eşyayı yönetebilir mi?
-- ADMIN her şeyi; STAFF sadece kendi kurumundaki eşyaları
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION assert_can_manage_found(p_user_id BIGINT, p_found_id BIGINT)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_role      VARCHAR(20);
    v_user_org  INTEGER;
    v_item_org  INTEGER;
BEGIN
    SELECT r.code, u.organization_id
    INTO v_role, v_user_org
    FROM users u
    JOIN roles r ON r.role_id = u.role_id
    WHERE u.user_id = p_user_id AND u.is_active;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kullanıcı bulunamadı ya da pasif: %', p_user_id;
    END IF;

    SELECT l.organization_id
    INTO v_item_org
    FROM found_reports f
    JOIN locations l ON l.location_id = f.location_id
    WHERE f.found_report_id = p_found_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bulunan bildirimi bulunamadı: %', p_found_id;
    END IF;

    IF v_role = 'ADMIN' OR (v_role = 'STAFF' AND v_user_org = v_item_org) THEN
        RETURN;
    END IF;

    RAISE EXCEPTION 'Bu işlem için yetkiniz yok (kullanıcı %)', p_user_id
        USING ERRCODE = 'insufficient_privilege';
END;
$$;

-- ---------------------------------------------------------
-- Talep açılmadan önce: eşya talep edilebilir mi, kayıp bildirimi talep sahibinin mi?
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_claims_before_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status  VARCHAR(20);
    v_owner   BIGINT;
BEGIN
    SELECT status INTO v_status
    FROM found_reports
    WHERE found_report_id = NEW.found_report_id
    FOR UPDATE;

    IF v_status NOT IN ('IN_STORAGE', 'CLAIM_PENDING') THEN
        RAISE EXCEPTION 'Bu eşya için talep açılamaz (durum: %)', v_status
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.lost_report_id IS NOT NULL THEN
        SELECT user_id INTO v_owner
        FROM lost_reports
        WHERE lost_report_id = NEW.lost_report_id;

        IF v_owner IS DISTINCT FROM NEW.claimant_user_id THEN
            RAISE EXCEPTION 'Talep sahibi bu kayıp bildiriminin sahibi değil'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_claims_before_insert
    BEFORE INSERT ON claims
    FOR EACH ROW EXECUTE FUNCTION trg_claims_before_insert();

-- ---------------------------------------------------------
-- Talep açıldıktan sonra: eşya CLAIM_PENDING, eşleşme CONFIRMED
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_claims_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE found_reports
    SET status = 'CLAIM_PENDING'
    WHERE found_report_id = NEW.found_report_id
      AND status = 'IN_STORAGE';

    IF NEW.match_id IS NOT NULL THEN
        UPDATE matches
        SET status = 'CONFIRMED'
        WHERE match_id = NEW.match_id
          AND status = 'SUGGESTED';
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_claims_after_insert
    AFTER INSERT ON claims
    FOR EACH ROW EXECUTE FUNCTION trg_claims_after_insert();

-- ---------------------------------------------------------
-- Personel talebi inceler: onay ya da ret
-- CALL review_claim(talep_id, personel_id, true);
-- CALL review_claim(talep_id, personel_id, false, 'Gizli detay uyuşmadı');
-- ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE review_claim(
    p_claim_id  BIGINT,
    p_staff_id  BIGINT,
    p_approve   BOOLEAN,
    p_reason    TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    c        RECORD;
    v_title  TEXT;
BEGIN
    SELECT * INTO c FROM claims WHERE claim_id = p_claim_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Talep bulunamadı: %', p_claim_id;
    END IF;

    PERFORM assert_can_manage_found(p_staff_id, c.found_report_id);

    IF c.status <> 'PENDING' THEN
        RAISE EXCEPTION 'Sadece bekleyen talepler incelenebilir (durum: %)', c.status;
    END IF;

    -- Durum geçmişinde işlemi bu personel yapmış görünsün
    PERFORM set_config('app.current_user_id', p_staff_id::text, true);

    SELECT i.title INTO v_title
    FROM found_reports f
    JOIN items i ON i.item_id = f.item_id
    WHERE f.found_report_id = c.found_report_id;

    IF p_approve THEN
        UPDATE claims
        SET status = 'APPROVED', reviewed_by = p_staff_id, reviewed_at = now()
        WHERE claim_id = p_claim_id;

        INSERT INTO notifications (user_id, type, claim_id, message)
        VALUES (c.claimant_user_id, 'CLAIM_APPROVED', p_claim_id,
                format('"%s" için talebiniz onaylandı. Kimliğinizle Kayıp Eşya Ofisi''nden teslim alabilirsiniz.', v_title));
    ELSE
        UPDATE claims
        SET status = 'REJECTED', reviewed_by = p_staff_id, reviewed_at = now(),
            reject_reason = p_reason
        WHERE claim_id = p_claim_id;

        INSERT INTO notifications (user_id, type, claim_id, message)
        VALUES (c.claimant_user_id, 'CLAIM_REJECTED', p_claim_id,
                format('"%s" için talebiniz reddedildi: %s', v_title, coalesce(p_reason, '-')));

        -- Başka bekleyen/onaylı talep kalmadıysa eşya emanete döner
        IF NOT EXISTS (
            SELECT 1 FROM claims
            WHERE found_report_id = c.found_report_id
              AND status IN ('PENDING', 'APPROVED')
        ) THEN
            UPDATE found_reports
            SET status = 'IN_STORAGE'
            WHERE found_report_id = c.found_report_id
              AND status = 'CLAIM_PENDING';
        END IF;
    END IF;
END;
$$;

-- ---------------------------------------------------------
-- Teslim: hepsi tek transaction içinde; bir adım bile hata verirse hiçbiri kaydedilmez
-- CALL complete_handover(talep_id, personel_id, 'ID_CARD', 'not');
-- ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE complete_handover(
    p_claim_id  BIGINT,
    p_staff_id  BIGINT,
    p_method    VARCHAR,
    p_notes     TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    c               RECORD;
    v_found_status  VARCHAR(20);
BEGIN
    SELECT * INTO c FROM claims WHERE claim_id = p_claim_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Talep bulunamadı: %', p_claim_id;
    END IF;

    -- 1) Eşyayı kilitle: aynı eşya aynı anda iki kez teslim edilemesin
    SELECT status INTO v_found_status
    FROM found_reports
    WHERE found_report_id = c.found_report_id
    FOR UPDATE;

    -- 2) Kilidi aldıktan sonra talebi tekrar oku (beklerken değişmiş olabilir)
    SELECT * INTO c FROM claims WHERE claim_id = p_claim_id FOR UPDATE;

    -- 3) Kontroller
    PERFORM assert_can_manage_found(p_staff_id, c.found_report_id);

    IF c.status <> 'APPROVED' THEN
        RAISE EXCEPTION 'Talep onaylanmamış (durum: %)', c.status;
    END IF;

    IF v_found_status <> 'CLAIM_PENDING' THEN
        RAISE EXCEPTION 'Eşya teslim edilebilir durumda değil (durum: %)', v_found_status;
    END IF;

    PERFORM set_config('app.current_user_id', p_staff_id::text, true);

    -- 4) Teslim kaydı
    INSERT INTO handovers (claim_id, staff_user_id, verification_method, notes)
    VALUES (p_claim_id, p_staff_id, p_method, p_notes);

    -- 5) Eşya teslim edildi
    UPDATE found_reports
    SET status = 'HANDED_OVER'
    WHERE found_report_id = c.found_report_id;

    -- 6) Kayıp bildirimi çözüldü
    IF c.lost_report_id IS NOT NULL THEN
        UPDATE lost_reports
        SET status = 'RESOLVED'
        WHERE lost_report_id = c.lost_report_id
          AND status = 'OPEN';
    END IF;

    -- 7) Aynı eşya için bekleyen diğer talepleri reddet ve haber ver
    WITH rejected AS (
        UPDATE claims
        SET status = 'REJECTED', reviewed_by = p_staff_id, reviewed_at = now(),
            reject_reason = 'Eşya, sahipliğini kanıtlayan başka bir kişiye teslim edildi.'
        WHERE found_report_id = c.found_report_id
          AND status = 'PENDING'
        RETURNING claim_id, claimant_user_id
    )
    INSERT INTO notifications (user_id, type, claim_id, message)
    SELECT claimant_user_id, 'CLAIM_REJECTED', claim_id,
           'Talep ettiğiniz eşya, sahipliğini kanıtlayan başka bir kişiye teslim edildi.'
    FROM rejected;

    -- 8) Bu eşya ya da bu kayıp için açık kalan eşleşme önerilerini kapat
    UPDATE matches
    SET status = 'DISMISSED'
    WHERE status = 'SUGGESTED'
      AND (found_report_id = c.found_report_id OR lost_report_id = c.lost_report_id);
END;
$$;