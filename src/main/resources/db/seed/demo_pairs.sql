-- =========================================================
-- demo_pairs.sql: Eşleştirme doğruluk testi
-- 20 kayıp + 20 gerçek eş + 6 tuzak. seed.sql'den SONRA çalıştırılır.
-- secret_details burada sadece test etiketi olarak kullanılıyor:
--   'DEMO-01'  = kayıp bildirimi ve onun gerçek eşi
--   'DEMO-X01' = 01 için tuzak (benzer ama yanlış)
-- =========================================================

DO $$
DECLARE
    t0       TIMESTAMPTZ := date_trunc('day', now()) - INTERVAL '3 days';
    r        RECORD;
    v_item   BIGINT;
    v_user   BIGINT  := (SELECT user_id FROM users WHERE email = 'kullanici2@ornek.com');
    v_staff  BIGINT  := (SELECT user_id FROM users WHERE email = 'personel1@ornek.com');
    v_ofis   INTEGER := (SELECT location_id FROM locations WHERE name = 'Kayıp Eşya Ofisi');
BEGIN
    -- -----------------------------------------------------
    -- 1) Kayıp bildirimleri (yolcunun anlattığı)
    --    start_h: t0'dan kaç saat sonra kaybetmeye başladı, span_h: aralık kaç saat
    -- -----------------------------------------------------
    FOR r IN
        SELECT * FROM (VALUES
            ('DEMO-01', 'Telefon',                'Siyah',      'Apple',     'Siyah iPhone 13',         'Kırmızı kılıf, arkasında çıkartma var',             'Dış Hatlar Terminali > Gidiş Katı > Güvenlik Kontrol',  10, 1),
            ('DEMO-02', 'Laptop',                 'Gri',        'Lenovo',    'Gri Lenovo laptop',       'ThinkPad, üzerinde NASA çıkartması var',            'Dış Hatlar Terminali > Gidiş Katı > Yeme-İçme Alanı',    8, 2),
            ('DEMO-03', 'Kulaklık',               'Beyaz',      'Apple',     'AirPods Pro',             'Beyaz kutusunda, kutunun üstünde çizik var',        'Uçak İçi',                                               5, 4),
            ('DEMO-04', 'Sırt Çantası',           'Lacivert',   'Herschel',  'Lacivert sırt çantası',   'İçinde ders kitapları ve mavi matara var',          'Metro İstasyonu',                                        7, 1),
            ('DEMO-05', 'Bavul',                  'Kırmızı',    'Samsonite', 'Kırmızı Samsonite bavul', 'Orta boy, sapında sarı kurdele bağlı',              'Dış Hatlar Terminali > Geliş Katı > Bagaj Alım Salonu', 20, 2),
            ('DEMO-06', 'Cüzdan',                 'Kahverengi', NULL,        'Kahverengi deri cüzdan',  'İçinde öğrenci kartı var',                          'İç Hatlar Terminali > Gidiş Katı > Check-in Salonu',     6, 1),
            ('DEMO-07', 'Pasaport',               'Lacivert',   NULL,        'Türk pasaportu',          'Lacivert kılıf içinde, arasında uçuş kartı var',    'Dış Hatlar Terminali > Gidiş Katı > Pasaport Kontrol',  13, 1),
            ('DEMO-08', 'Kimlik Kartı',           'Mavi',       NULL,        'Kimlik kartı',            'Şeffaf kartlık içinde, yanında metro kartı',        'İç Hatlar Terminali > Geliş Katı > Karşılama Salonu',   16, 2),
            ('DEMO-09', 'Ev Anahtarı',            'Gümüş',      NULL,        'Anahtarlık',              'Üç anahtar, kırmızı futbol topu anahtarlığı',       'Otopark > Katlı Otopark',                                9, 1),
            ('DEMO-10', 'Araba Anahtarı',         'Siyah',      'Toyota',    'Toyota araba anahtarı',   'Kumandalı, deri kılıflı',                           'Otopark > Açık Otopark',                                12, 1),
            ('DEMO-11', 'Mont / Ceket',           'Yeşil',      'Columbia',  'Yeşil mont',              'Kapüşonlu, cebinde eldiven var',                    'Dış Hatlar Terminali > Gidiş Katı > Duty Free Alanı',   10, 2),
            ('DEMO-12', 'Atkı / Şal',             'Bej',        NULL,        'Bej yün atkı',            'Ekose desenli, uzun',                               'Uçak İçi',                                               0, 4),
            ('DEMO-13', 'Gözlük',                 'Siyah',      'Ray-Ban',   'Siyah güneş gözlüğü',     'Ray-Ban, kahverengi kılıfı ile birlikte',           'İç Hatlar Terminali > Gidiş Katı > Biniş Kapıları',     15, 1),
            ('DEMO-14', 'Şemsiye',                'Mor',        NULL,        'Mor şemsiye',             'Katlanır, sapı tahta',                              'Metro İstasyonu',                                       18, 1),
            ('DEMO-15', 'Kol Saati',              'Altın',      'Casio',     'Altın rengi Casio saat',  'Metal kordon, camında küçük çizik',                 'Dış Hatlar Terminali > Gidiş Katı > Güvenlik Kontrol',   7, 1),
            ('DEMO-16', 'Kolye',                  'Altın',      NULL,        'Altın kolye',             'İnce zincir, kalp şeklinde ucu var',                'Dış Hatlar Terminali > Geliş Katı > Gümrük Çıkışı',     21, 1),
            ('DEMO-17', 'Tablet',                 'Gri',        'Samsung',   'Samsung Galaxy Tab',      'Siyah klavyeli kılıf içinde',                       'İç Hatlar Terminali > Gidiş Katı > Yeme-İçme Alanı',    11, 1),
            ('DEMO-18', 'Şarj Aleti / Powerbank', 'Beyaz',      'Xiaomi',    'Beyaz powerbank',         'Xiaomi 10000 mAh, kablosu takılı',                  'Dış Hatlar Terminali > Gidiş Katı > Biniş Kapıları',     3, 2),
            ('DEMO-19', 'Kitap / Defter',         'Kırmızı',    NULL,        'Kırmızı defter',          'Kapağında üniversite logosu, içinde ders notları', 'İç Hatlar Terminali > Geliş Katı > Bagaj Alım Salonu',  14, 1),
            ('DEMO-20', 'Akıllı Saat',            'Siyah',      'Apple',     'Apple Watch',             'Siyah spor kordon',                                 'Dış Hatlar Terminali > Gidiş Katı > Check-in Salonu',    9, 1)
        ) AS v(tag, category, color, brand, title, description, loc_path, start_h, span_h)
    LOOP
        INSERT INTO items (kind, category_id, color_id, brand, title, description, secret_details)
        VALUES ('LOST',
                (SELECT category_id FROM categories WHERE name = r.category AND parent_category_id IS NOT NULL),
                (SELECT color_id FROM colors WHERE name = r.color),
                r.brand, r.title, r.description, r.tag)
        RETURNING item_id INTO v_item;

        INSERT INTO lost_reports (item_id, user_id, location_id, lost_from, lost_to)
        VALUES (v_item, v_user,
                (SELECT location_id FROM locations WHERE location_path(location_id) = r.loc_path),
                t0 + r.start_h * INTERVAL '1 hour',
                t0 + (r.start_h + r.span_h) * INTERVAL '1 hour');
    END LOOP;

    -- -----------------------------------------------------
    -- 2) Bulunan bildirimleri: 20 gerçek eş + 6 tuzak (personelin yazdığı)
    --    found_h: t0'dan kaç saat sonra bulundu
    -- -----------------------------------------------------
    FOR r IN
        SELECT * FROM (VALUES
            ('DEMO-01',  'Telefon',                'Siyah',      'Apple',     'iPhone',                    'Kırmızı kılıflı, arkada çıkartma var',               'Dış Hatlar Terminali > Gidiş Katı > Güvenlik Kontrol',  11.5),
            ('DEMO-02',  'Laptop',                 'Gri',        'Lenovo',    'Lenovo dizüstü bilgisayar', 'Gri ThinkPad, NASA çıkartmalı',                      'Dış Hatlar Terminali > Gidiş Katı',                      12),
            ('DEMO-03',  'Kulaklık',               'Beyaz',      NULL,        'Kablosuz kulaklık',         'Beyaz kutuda, kutu çizik',                           'Uçak İçi',                                               10),
            ('DEMO-04',  'Sırt Çantası',           'Lacivert',   'Herschel',  'Sırt çantası',              'Lacivert, içinde kitaplar ve matara',                'Metro İstasyonu',                                         9),
            ('DEMO-05',  'Bavul',                  'Kırmızı',    'Samsonite', 'Kırmızı bavul',             'Sapında sarı kurdele, orta boy',                     'Dış Hatlar Terminali > Geliş Katı > Bagaj Alım Salonu', 30),
            ('DEMO-06',  'Cüzdan',                 'Kahverengi', NULL,        'Deri cüzdan',               'Kahverengi deri cüzdan, içinde öğrenci kartı',      'İç Hatlar Terminali > Gidiş Katı > Güvenlik Kontrol',    7.5),
            ('DEMO-07',  'Pasaport',               'Lacivert',   NULL,        'Pasaport',                  'Lacivert kılıflı Türk pasaportu, içinde uçuş kartı', 'Dış Hatlar Terminali > Gidiş Katı > Pasaport Kontrol',  13.5),
            ('DEMO-08',  'Kimlik Kartı',           'Mavi',       NULL,        'Kimlik kartı',              'Şeffaf kartlıkta kimlik ve metro kartı',             'İç Hatlar Terminali > Geliş Katı',                       19),
            ('DEMO-09',  'Ev Anahtarı',            'Gümüş',      NULL,        'Anahtar destesi',           'Üç anahtar, futbol topu anahtarlıklı',               'Otopark > Katlı Otopark',                                11),
            ('DEMO-10',  'Araba Anahtarı',         'Siyah',      'Toyota',    'Araba anahtarı',            'Toyota, deri kılıflı kumanda',                       'Otopark',                                                15),
            ('DEMO-11',  'Mont / Ceket',           'Yeşil',      'Columbia',  'Mont',                      'Yeşil kapüşonlu mont, cebinde eldiven',              'Dış Hatlar Terminali > Gidiş Katı > Yeme-İçme Alanı',   13),
            ('DEMO-12',  'Atkı / Şal',             NULL,         NULL,        'Atkı',                      'Ekose desenli yün atkı',                             'Uçak İçi',                                                6),
            ('DEMO-13',  'Gözlük',                 'Siyah',      'Ray-Ban',   'Güneş gözlüğü',             'Siyah Ray-Ban, kahverengi kılıflı',                  'İç Hatlar Terminali > Gidiş Katı > Biniş Kapıları',     16.5),
            ('DEMO-14',  'Şemsiye',                'Mor',        NULL,        'Şemsiye',                   'Mor katlanır şemsiye, tahta saplı',                  'Metro İstasyonu',                                        40),
            ('DEMO-15',  'Kol Saati',              'Altın',      'Casio',     'Kol saati',                 'Casio, metal kordon, cam çizik',                     'Dış Hatlar Terminali > Gidiş Katı > Güvenlik Kontrol',   8.5),
            ('DEMO-16',  'Kolye',                  'Altın',      NULL,        'Kolye',                     'Kalp uçlu ince altın zincir',                        'Dış Hatlar Terminali > Geliş Katı > Karşılama Salonu',  23),
            ('DEMO-17',  'Tablet',                 'Gri',        'Samsung',   'Tablet',                    'Samsung, siyah klavyeli kılıfta',                    'İç Hatlar Terminali > Gidiş Katı > Yeme-İçme Alanı',    60),
            ('DEMO-18',  'Şarj Aleti / Powerbank', 'Beyaz',      'Xiaomi',    'Powerbank',                 'Beyaz Xiaomi, kablolu',                              'Dış Hatlar Terminali > Gidiş Katı > Biniş Kapıları',     6),
            ('DEMO-19',  'Diğer',                  'Kırmızı',    NULL,        'Defter',                    'Kırmızı kapaklı, ders notları var',                  'İç Hatlar Terminali > Geliş Katı > Bagaj Alım Salonu',  15.2),
            ('DEMO-20',  'Akıllı Saat',            'Siyah',      NULL,        'Akıllı saat',               'Siyah spor kordonlu',                                'Dış Hatlar Terminali > Gidiş Katı > Check-in Salonu',   10.5),
            -- Tuzaklar
            ('DEMO-X01', 'Telefon',                'Siyah',      'Samsung',   'Samsung telefon',           'Siyah, kılıfsız',                                    'Dış Hatlar Terminali > Gidiş Katı > Güvenlik Kontrol',  12),
            ('DEMO-X02', 'Laptop',                 'Gri',        'HP',        'HP laptop',                 'Gri dizüstü, çıkartmasız',                           'Dış Hatlar Terminali > Gidiş Katı > Yeme-İçme Alanı',   11),
            ('DEMO-X03', 'Kulaklık',               'Siyah',      'Sony',      'Sony kulaklık',             'Kulak üstü, siyah',                                  'Uçak İçi',                                                8),
            ('DEMO-X05', 'Bavul',                  'Siyah',      'Samsonite', 'Siyah bavul',               'Büyük boy, sert kasa',                               'Dış Hatlar Terminali > Geliş Katı > Bagaj Alım Salonu', 23),
            ('DEMO-X06', 'Cüzdan',                 'Kahverengi', NULL,        'Cüzdan',                    'Kahverengi cüzdan, boş',                             'İç Hatlar Terminali > Gidiş Katı > Check-in Salonu',    55),
            ('DEMO-X13', 'Gözlük',                 'Siyah',      'Polaroid',  'Gözlük',                    'Siyah çerçeveli güneş gözlüğü',                      'İç Hatlar Terminali > Gidiş Katı > Güvenlik Kontrol',   16)
        ) AS v(tag, category, color, brand, title, description, loc_path, found_h)
    LOOP
        INSERT INTO items (kind, category_id, color_id, brand, title, description, secret_details)
        VALUES ('FOUND',
                (SELECT category_id FROM categories WHERE name = r.category AND parent_category_id IS NOT NULL),
                (SELECT color_id FROM colors WHERE name = r.color),
                r.brand, r.title, r.description, r.tag)
        RETURNING item_id INTO v_item;

        INSERT INTO found_reports (item_id, finder_user_id, location_id, storage_location_id, found_at)
        VALUES (v_item, v_staff,
                (SELECT location_id FROM locations WHERE location_path(location_id) = r.loc_path),
                v_ofis,
                t0 + r.found_h * INTERVAL '1 hour');
    END LOOP;

    RAISE NOTICE 'Demo verisi eklendi.';
END;
$$;