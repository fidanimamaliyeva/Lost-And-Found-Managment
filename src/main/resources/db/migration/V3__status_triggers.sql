-- =========================================================
-- V3: Trigger'lar
-- =========================================================

-- ---------------------------------------------------------
-- 1) updated_at alanını otomatik güncelle
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;          -- BEFORE trigger'da değiştirilmiş satırı geri döndürmek şart
END;
$$;

CREATE TRIGGER trg_lost_reports_updated_at
    BEFORE UPDATE ON lost_reports
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

CREATE TRIGGER trg_found_reports_updated_at
    BEFORE UPDATE ON found_reports
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();


-- ---------------------------------------------------------
-- 2) İzin verilen durum geçişleri (kural tablosu) + kontrol trigger'ı
-- ---------------------------------------------------------
CREATE TABLE allowed_status_transitions (
    entity       VARCHAR(20) NOT NULL,
    from_status  VARCHAR(20) NOT NULL,
    to_status    VARCHAR(20) NOT NULL,
    CONSTRAINT pk_allowed_status_transitions PRIMARY KEY (entity, from_status, to_status),
    CONSTRAINT chk_allowed_transitions_entity
        CHECK (entity IN ('LOST_REPORT', 'FOUND_REPORT', 'CLAIM', 'MATCH'))
);

INSERT INTO allowed_status_transitions (entity, from_status, to_status) VALUES
    -- Kayıp bildirimi
    ('LOST_REPORT',  'OPEN',          'RESOLVED'),     -- eşya teslim edildi
    ('LOST_REPORT',  'OPEN',          'CANCELLED'),    -- kullanıcı iptal etti
    ('LOST_REPORT',  'OPEN',          'EXPIRED'),      -- süresi doldu
    -- Bulunan eşya
    ('FOUND_REPORT', 'IN_STORAGE',    'CLAIM_PENDING'),
    ('FOUND_REPORT', 'CLAIM_PENDING', 'IN_STORAGE'),   -- talep reddedildi
    ('FOUND_REPORT', 'CLAIM_PENDING', 'HANDED_OVER'),
    ('FOUND_REPORT', 'IN_STORAGE',    'DISPOSED'),     -- sahibi çıkmadı
    -- Sahiplenme talebi
    ('CLAIM',        'PENDING',       'APPROVED'),
    ('CLAIM',        'PENDING',       'REJECTED'),
    ('CLAIM',        'PENDING',       'CANCELLED'),
    -- Eşleşme
    ('MATCH',        'SUGGESTED',     'CONFIRMED'),
    ('MATCH',        'SUGGESTED',     'DISMISSED');

CREATE OR REPLACE FUNCTION trg_check_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Durum değişmediyse kontrol etme
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT EXISTS (
            SELECT 1
            FROM allowed_status_transitions t
            WHERE t.entity      = TG_ARGV[0]
              AND t.from_status = OLD.status
              AND t.to_status   = NEW.status
        ) THEN
            RAISE EXCEPTION 'Geçersiz durum geçişi (%): % -> %',
                            TG_ARGV[0], OLD.status, NEW.status
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- Aynı fonksiyon 4 tabloda; TG_ARGV[0] hangi kural setinin kullanılacağını söyler
CREATE TRIGGER trg_lost_reports_status_check
    BEFORE UPDATE OF status ON lost_reports
    FOR EACH ROW EXECUTE FUNCTION trg_check_status_transition('LOST_REPORT');

CREATE TRIGGER trg_found_reports_status_check
    BEFORE UPDATE OF status ON found_reports
    FOR EACH ROW EXECUTE FUNCTION trg_check_status_transition('FOUND_REPORT');

CREATE TRIGGER trg_claims_status_check
    BEFORE UPDATE OF status ON claims
    FOR EACH ROW EXECUTE FUNCTION trg_check_status_transition('CLAIM');

CREATE TRIGGER trg_matches_status_check
    BEFORE UPDATE OF status ON matches
    FOR EACH ROW EXECUTE FUNCTION trg_check_status_transition('MATCH');


-- ---------------------------------------------------------
-- 3) Durum geçmişini otomatik yaz
-- ---------------------------------------------------------
-- changed_by: backend her işlemde "SET LOCAL app.current_user_id = '<id>'" yapar.
-- Ayar yoksa NULL yazılır (örn. sistem/elle yapılan işlemler).
CREATE OR REPLACE FUNCTION trg_log_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_status  VARCHAR(20);
    v_changed_by  BIGINT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_old_status := NULL;            -- yeni kayıt: önceki durum yok
    ELSE
        v_old_status := OLD.status;
    END IF;

    v_changed_by := NULLIF(current_setting('app.current_user_id', true), '')::BIGINT;

    IF TG_TABLE_NAME = 'lost_reports' THEN
        INSERT INTO report_status_history (lost_report_id, old_status, new_status, changed_by)
        VALUES (NEW.lost_report_id, v_old_status, NEW.status, v_changed_by);
    ELSE
        INSERT INTO report_status_history (found_report_id, old_status, new_status, changed_by)
        VALUES (NEW.found_report_id, v_old_status, NEW.status, v_changed_by);
    END IF;

    RETURN NULL;                         -- AFTER trigger'da dönüş değeri kullanılmaz
END;
$$;

CREATE TRIGGER trg_lost_reports_log_insert
    AFTER INSERT ON lost_reports
    FOR EACH ROW EXECUTE FUNCTION trg_log_status_change();

CREATE TRIGGER trg_lost_reports_log_update
    AFTER UPDATE OF status ON lost_reports
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION trg_log_status_change();

CREATE TRIGGER trg_found_reports_log_insert
    AFTER INSERT ON found_reports
    FOR EACH ROW EXECUTE FUNCTION trg_log_status_change();

CREATE TRIGGER trg_found_reports_log_update
    AFTER UPDATE OF status ON found_reports
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION trg_log_status_change();


-- ---------------------------------------------------------
-- 4) STAFF kullanıcısının kurumu olmalı, diğerlerinin olmamalı
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_check_user_organization()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_role_code VARCHAR(20);
BEGIN
    SELECT code INTO v_role_code FROM roles WHERE role_id = NEW.role_id;

    IF v_role_code = 'STAFF' AND NEW.organization_id IS NULL THEN
        RAISE EXCEPTION 'STAFF kullanıcısının bir kurumu olmalı'
            USING ERRCODE = 'check_violation';
    ELSIF v_role_code <> 'STAFF' AND NEW.organization_id IS NOT NULL THEN
        RAISE EXCEPTION 'Sadece STAFF kullanıcılarının kurumu olabilir'
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_organization_check
    BEFORE INSERT OR UPDATE OF role_id, organization_id ON users
    FOR EACH ROW EXECUTE FUNCTION trg_check_user_organization();