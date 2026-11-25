# Lost & Found – Kayıp Eşya Eşleştirme ve Yönetim Sistemi

Veri Tabanı Yönetim Sistemleri dersi projesi.

## Kurulum
1. PostgreSQL 1X kur (herkes aynı ana sürüm).
2. pgAdmin'de postgres kullanıcısıyla `scripts/create_database.sql` dosyasını çalıştır.
3. Bağlantı: localhost:5432, veritabanı / kullanıcı / şifre: lostfound
4. (İsteğe bağlı) Test verisi: pgAdmin'de lostfound bağlantısıyla `src/main/resources/db/seed/seed.sql` dosyasını çalıştır.

## Ekip
- Veritabanı: İlayda Genç
- Backend: ...
- Frontend: ...

## Kurallar
- `main` dalına doğrudan push yok; her değişiklik Pull Request ile.
- Branch adları: `db/...`, `be/...`, `fe/...`
- `main`'e girmiş migration dosyası değiştirilmez, yeni dosya açılır.
