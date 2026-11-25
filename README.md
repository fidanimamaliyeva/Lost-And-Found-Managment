# Lost & Found – Kayıp Eşya Eşleştirme ve Yönetim Sistemi

Veri Tabanı Yönetim Sistemleri dersi projesi.

## Kurulum
1. PostgreSQL 1X kur (herkes aynı ana sürüm).
2. pgAdmin'de postgres kullanıcısıyla `scripts/create_database.sql` dosyasını çalıştır (iki satırı ayrı ayrı).
3. Uygulamayı başlat; Flyway tabloları kendisi oluşturur.
4. (İsteğe bağlı) Test verisi: `src/main/resources/db/seed/seed.sql`, sonra `demo_pairs.sql`.

Ayrıntılar ve backend notları: [docs/database.md](docs/database.md)

## Ekip
- Veritabanı: İlayda Genç
- Backend: ...
- Frontend: ...

## Kurallar
- `main` dalına doğrudan push yok; her değişiklik Pull Request ile.
- Branch adları: `db/...`, `be/...`, `fe/...`
- `main`'e girmiş migration dosyası değiştirilmez, yeni dosya açılır.
