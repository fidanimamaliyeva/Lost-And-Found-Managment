-- =========================================================
-- V8: Index'ler
-- Not: PK ve UNIQUE kısıtları kendi index'lerini zaten oluşturur
-- (örn. uq_matches_pair, uq_claims_one_per_user). Onları tekrar eklemiyoruz.
-- =========================================================

-- Metin araması için trigram eklentisi
-- ("%iphone%" gibi ortadan arama B-tree ile hızlanmaz, GIN + trigram gerekir)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Kayıp bildirimleri
CREATE INDEX idx_lost_reports_user_created
    ON lost_reports (user_id, created_at DESC);        -- "Kayıtlarım" sayfası
CREATE INDEX idx_lost_reports_location
    ON lost_reports (location_id);                     -- konum istatistikleri, FK
CREATE INDEX idx_lost_reports_created
    ON lost_reports (created_at);                      -- aylık istatistik
CREATE INDEX idx_lost_reports_open_lost_to
    ON lost_reports (lost_to) WHERE status = 'OPEN';   -- kısmi: eşleştirme sadece açık kayıplara bakar

-- Bulunan bildirimleri
CREATE INDEX idx_found_reports_storage_found_at
    ON found_reports (found_at) WHERE status = 'IN_STORAGE';  -- kısmi: eşleştirme adayları
CREATE INDEX idx_found_reports_location
    ON found_reports (location_id);
CREATE INDEX idx_found_reports_finder
    ON found_reports (finder_user_id);
CREATE INDEX idx_found_reports_created
    ON found_reports (created_at);

-- Eşyalar
CREATE INDEX idx_items_category_color
    ON items (category_id, color_id);                  -- filtreleme
CREATE INDEX idx_items_title_trgm
    ON items USING gin (title gin_trgm_ops);           -- başlıkta arama
CREATE INDEX idx_items_description_trgm
    ON items USING gin (description gin_trgm_ops);     -- açıklamada arama

-- Eşleşme, talep, teslim, bildirim, geçmiş
CREATE INDEX idx_matches_found
    ON matches (found_report_id);                      -- (lost, found) için uq_matches_pair zaten var
CREATE INDEX idx_claims_claimant
    ON claims (claimant_user_id);                      -- "Taleplerim"
CREATE INDEX idx_handovers_staff
    ON handovers (staff_user_id);
CREATE INDEX idx_handovers_date
    ON handovers (handed_over_at);
CREATE INDEX idx_notifications_user_unread
    ON notifications (user_id, created_at DESC) WHERE NOT is_read;  -- okunmamış bildirimler
CREATE INDEX idx_history_lost
    ON report_status_history (lost_report_id);
CREATE INDEX idx_history_found
    ON report_status_history (found_report_id);