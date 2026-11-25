-- =========================================================
-- V2: Sabit veriler (roller, renkler, kategoriler, örnek kurumlar ve konumlar)
-- =========================================================

-- Roller
INSERT INTO roles (code) VALUES ('USER'), ('STAFF'), ('ADMIN');

-- Renkler
INSERT INTO colors (name) VALUES
    ('Siyah'), ('Beyaz'), ('Gri'), ('Gümüş'), ('Altın'),
    ('Kırmızı'), ('Pembe'), ('Turuncu'), ('Sarı'), ('Yeşil'),
    ('Mavi'), ('Lacivert'), ('Mor'), ('Kahverengi'), ('Bej'),
    ('Çok renkli');

-- Ana kategoriler
INSERT INTO categories (name) VALUES
    ('Elektronik'), ('Çanta ve Bavul'), ('Cüzdan ve Kart'), ('Kimlik ve Belge'),
    ('Anahtar'), ('Giyim ve Aksesuar'), ('Takı ve Saat'), ('Diğer');

-- Alt kategoriler (üst kategori adıyla bulunur, ID elle yazılmaz)
INSERT INTO categories (parent_category_id, name)
SELECT c.category_id, v.name
FROM (VALUES
    ('Elektronik',        'Telefon'),
    ('Elektronik',        'Laptop'),
    ('Elektronik',        'Tablet'),
    ('Elektronik',        'Kulaklık'),
    ('Elektronik',        'Şarj Aleti / Powerbank'),
    ('Elektronik',        'Akıllı Saat'),
    ('Elektronik',        'Kamera'),
    ('Çanta ve Bavul',    'Sırt Çantası'),
    ('Çanta ve Bavul',    'El Çantası'),
    ('Çanta ve Bavul',    'Bavul'),
    ('Çanta ve Bavul',    'Laptop Çantası'),
    ('Cüzdan ve Kart',    'Cüzdan'),
    ('Cüzdan ve Kart',    'Kartlık'),
    ('Cüzdan ve Kart',    'Banka Kartı'),
    ('Kimlik ve Belge',   'Kimlik Kartı'),
    ('Kimlik ve Belge',   'Pasaport'),
    ('Kimlik ve Belge',   'Ehliyet'),
    ('Kimlik ve Belge',   'Öğrenci Kartı'),
    ('Kimlik ve Belge',   'Diğer Belge'),
    ('Anahtar',           'Ev Anahtarı'),
    ('Anahtar',           'Araba Anahtarı'),
    ('Giyim ve Aksesuar', 'Mont / Ceket'),
    ('Giyim ve Aksesuar', 'Atkı / Şal'),
    ('Giyim ve Aksesuar', 'Şapka'),
    ('Giyim ve Aksesuar', 'Gözlük'),
    ('Giyim ve Aksesuar', 'Şemsiye'),
    ('Takı ve Saat',      'Yüzük'),
    ('Takı ve Saat',      'Kolye'),
    ('Takı ve Saat',      'Bilezik'),
    ('Takı ve Saat',      'Küpe'),
    ('Takı ve Saat',      'Kol Saati'),
    ('Diğer',             'Kitap / Defter'),
    ('Diğer',             'Oyuncak'),
    ('Diğer',             'Spor Malzemesi'),
    ('Diğer',             'Diğer')
) AS v(parent_name, name)
JOIN categories c
  ON c.name = v.parent_name
 AND c.parent_category_id IS NULL;

-- Kurum (uygulama şimdilik sadece İstanbul Havalimanı için)
INSERT INTO organizations (name, org_type, city)
VALUES ('İstanbul Havalimanı', 'AIRPORT', 'İstanbul');

-- Konumlar, 1. seviye: terminaller ve ana alanlar
INSERT INTO locations (organization_id, name, location_type)
SELECT o.organization_id, v.name, v.location_type
FROM (VALUES
    ('Dış Hatlar Terminali', 'TERMINAL'),
    ('İç Hatlar Terminali',  'TERMINAL'),
    ('Otopark',              'AREA'),
    ('Metro İstasyonu',      'STATION'),
    ('Uçak İçi',             'OTHER')
) AS v(name, location_type)
CROSS JOIN organizations o
WHERE o.name = 'İstanbul Havalimanı';

-- Konumlar, 2. seviye: katlar ve özel alanlar
INSERT INTO locations (organization_id, parent_location_id, name, location_type)
SELECT p.organization_id, p.location_id, v.name, v.location_type
FROM (VALUES
    ('Dış Hatlar Terminali', 'Gidiş Katı',       'FLOOR'),
    ('Dış Hatlar Terminali', 'Geliş Katı',       'FLOOR'),
    ('Dış Hatlar Terminali', 'Kayıp Eşya Ofisi', 'AREA'),
    ('İç Hatlar Terminali',  'Gidiş Katı',       'FLOOR'),
    ('İç Hatlar Terminali',  'Geliş Katı',       'FLOOR'),
    ('Otopark',              'Katlı Otopark',    'AREA'),
    ('Otopark',              'Açık Otopark',     'AREA')
) AS v(parent_name, name, location_type)
JOIN locations p
  ON p.name = v.parent_name
 AND p.parent_location_id IS NULL;

-- Konumlar, 3. seviye: katların içindeki alanlar
-- Üst konum = (terminal adı + kat adı) ile bulunur, çünkü "Gidiş Katı" iki terminalde de var
INSERT INTO locations (organization_id, parent_location_id, name, location_type)
SELECT kat.organization_id, kat.location_id, v.name, v.location_type
FROM (VALUES
    ('Dış Hatlar Terminali', 'Gidiş Katı', 'Check-in Salonu',   'AREA'),
    ('Dış Hatlar Terminali', 'Gidiş Katı', 'Güvenlik Kontrol',  'AREA'),
    ('Dış Hatlar Terminali', 'Gidiş Katı', 'Pasaport Kontrol',  'AREA'),
    ('Dış Hatlar Terminali', 'Gidiş Katı', 'Duty Free Alanı',   'AREA'),
    ('Dış Hatlar Terminali', 'Gidiş Katı', 'Yeme-İçme Alanı',   'AREA'),
    ('Dış Hatlar Terminali', 'Gidiş Katı', 'Biniş Kapıları',    'GATE'),
    ('Dış Hatlar Terminali', 'Geliş Katı', 'Bagaj Alım Salonu', 'AREA'),
    ('Dış Hatlar Terminali', 'Geliş Katı', 'Gümrük Çıkışı',     'AREA'),
    ('Dış Hatlar Terminali', 'Geliş Katı', 'Karşılama Salonu',  'AREA'),
    ('İç Hatlar Terminali',  'Gidiş Katı', 'Check-in Salonu',   'AREA'),
    ('İç Hatlar Terminali',  'Gidiş Katı', 'Güvenlik Kontrol',  'AREA'),
    ('İç Hatlar Terminali',  'Gidiş Katı', 'Yeme-İçme Alanı',   'AREA'),
    ('İç Hatlar Terminali',  'Gidiş Katı', 'Biniş Kapıları',    'GATE'),
    ('İç Hatlar Terminali',  'Geliş Katı', 'Bagaj Alım Salonu', 'AREA'),
    ('İç Hatlar Terminali',  'Geliş Katı', 'Karşılama Salonu',  'AREA')
) AS v(terminal_name, floor_name, name, location_type)
JOIN locations terminal
  ON terminal.name = v.terminal_name
 AND terminal.parent_location_id IS NULL
JOIN locations kat
  ON kat.parent_location_id = terminal.location_id
 AND kat.name = v.floor_name;