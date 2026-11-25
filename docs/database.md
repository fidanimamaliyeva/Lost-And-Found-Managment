# Veritabanı Rehberi

Sorumlu: Fidan Imamaliyeva (Kişi 1)
Kapsam: İstanbul Havalimanı kayıp eşya sistemi, PostgreSQL 18

## 1. Dosyalar ve çalışma sırası

| Dosya | İçerik | Kim çalıştırır |
| --- | --- | --- |
| `db/migration/V1__tables.sql` | 15 tablo, PK/FK/UNIQUE/CHECK kısıtları | Flyway |
| `db/migration/V2__lookup_data.sql` | Roller, 16 renk, 43 kategori, havalimanı ve 27 konum | Flyway |
| `db/migration/V3__status_triggers.sql` | `updated_at`, durum geçişi kontrolü, durum geçmişi, STAFF kurum kontrolü | Flyway |
| `db/migration/V4__public_views.sql` | `location_path()`, `v_public_found_items` | Flyway |
| `db/migration/V5__matching.sql` | Eşleştirme fonksiyonları, otomatik eşleştirme ve bildirim trigger'ları | Flyway |
| `db/migration/V6__handover.sql` | Talep trigger'ları, `review_claim`, `complete_handover` | Flyway |
| `db/migration/V7__stats_views.sql` | Yönetici paneli görünümleri | Flyway |
| `db/migration/V8__indexes.sql` | Index'ler, `pg_trgm` | Flyway |
| `db/seed/seed.sql` | 306 kullanıcı, 5.000 kayıp, 5.000 bulunan (test verisi) | Elle (pgAdmin) |
| `db/seed/demo_pairs.sql` | 20 demo çift + 6 tuzak (eşleştirme testi, sunum demosu) | Elle, seed'den sonra |

Kural: `main`'e girmiş bir migration dosyası değiştirilmez. Değişiklik yeni dosyayla yapılır (`V9__...sql`).

## 2. Kurulum

1. PostgreSQL 18 kur.
2. pgAdmin'de postgres kullanıcısıyla `scripts/create_database.sql` dosyasını çalıştır. İki satırı **ayrı ayrı** çalıştır.
3. Spring Boot uygulamasını başlat. Flyway V1–V8'i kendisi çalıştırır.
4. Test verisi için pgAdmin'de lostfound bağlantısıyla önce `seed.sql`, sonra `demo_pairs.sql` dosyasını çalıştır.

### Veritabanını sıfırlama

Tabloları daha önce elle oluşturduysan, Flyway'i ilk kez çalıştırmadan önce şunu yap (lostfound bağlantısıyla):

```sql
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
```

Sonra uygulamayı başlat. Bu komut **tüm verileri siler**.

## 3. Spring Boot ayarları (Kişi 2)

`application.properties`:

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/lostfound
spring.datasource.username=lostfound
spring.datasource.password=lostfound

# Şemayı Hibernate değil Flyway yönetir; Hibernate sadece kontrol eder
spring.jpa.hibernate.ddl-auto=validate
spring.flyway.enabled=true
```

Maven bağımlılıkları: `flyway-core` ve `flyway-database-postgresql` (Spring Boot 3 ile ikisi de gerekli).

## 4. Backend'in bilmesi gerekenler

### 4.1 İşlemi yapan kullanıcı

Durum geçmişinde (`report_status_history.changed_by`) kimin neyi değiştirdiği görünsün diye, durum değiştiren her transaction'ın başında şunu çalıştır:

```sql
SELECT set_config('app.current_user_id', :userId, true);
```

Üçüncü parametre `true` = sadece bu transaction için geçerli.

### 4.2 Veritabanının kendiliğinden yaptıkları (backend tekrar yapmamalı)

| Olay | Veritabanı ne yapar |
| --- | --- |
| `lost_reports` / `found_reports` INSERT | Eşleştirme çalışır (puan ≥ 50 → `matches`), kayıp sahibine `MATCH_FOUND` bildirimi, durum geçmişine kayıt |
| Herhangi bir bildirimde `status` UPDATE | İzinsiz geçiş reddedilir; geçmişe kayıt; `updated_at` güncellenir |
| `claims` INSERT | Eşya talep edilebilir mi ve kayıp bildirimi talep sahibinin mi kontrol edilir; eşya `CLAIM_PENDING`, eşleşme `CONFIRMED` olur |
| `users` INSERT/UPDATE | STAFF'ın kurumu var mı kontrol edilir |

### 4.3 Backend'in çağıracağı prosedürler

| Ne zaman | Çağrı |
| --- | --- |
| Personel talebi onaylar | `CALL review_claim(:claimId, :staffId, true)` |
| Personel talebi reddeder | `CALL review_claim(:claimId, :staffId, false, :reason)` (neden zorunlu) |
| Personel teslim eder | `CALL complete_handover(:claimId, :staffId, :method, :notes)` |

`method` değerleri: `ID_CARD`, `PROOF_OF_PURCHASE`, `SECRET_DETAILS`, `OTHER`.

Prosedürler yetkiyi kendileri kontrol eder. Personel sadece kendi kurumunun eşyalarını yönetebilir, ADMIN hepsini.

### 4.4 Hata kodları → HTTP

| SQLSTATE | Anlamı | Önerilen HTTP |
| --- | --- | --- |
| `23505` unique_violation | Aynı e-posta, aynı talep, ikinci onaylı talep | 409 Conflict |
| `23514` check_violation | Geçersiz değer ya da durum geçişi, talep açılamaz | 400 Bad Request |
| `23503` foreign_key_violation | Olmayan kategori/konum/kullanıcı | 400 Bad Request |
| `42501` insufficient_privilege | Yetkisiz inceleme/teslim | 403 Forbidden |
| `P0001` raise_exception | Prosedür kuralları (örn. "Talep onaylanmamış") | 400 Bad Request |

Hata mesajları Türkçe ve kullanıcıya gösterilebilir.

## 5. Frontend için hazır görünümler (Kişi 2 → Kişi 3)

| Görünüm | Kullanım |
| --- | --- |
| `v_public_found_items` | Herkese açık bulunan eşya listesi/arama. **Gizli detay ve kişisel bilgi içermez; herkese açık liste sadece buradan okunmalı.** |
| `v_match_rankings` | Kullanıcının eşleşmeleri, sırası ve seviyesi (HIGH/MEDIUM/LOW) |
| `v_admin_dashboard` | Panelin sayı kartları (tek satır) |
| `v_category_stats` | Kategori grafiği |
| `v_location_hotspots` | En yoğun konumlar |
| `v_monthly_stats` | Son 12 ay grafiği |

Form listeleri: `roles`, `categories` (ağaç: `parent_category_id`), `colors`, `locations` (tam yol için `location_path(location_id)`).

## 6. Durumlar ve izinli geçişler

Tüm kurallar `allowed_status_transitions` tablosunda.

| Kayıt | Durumlar | Geçişler |
| --- | --- | --- |
| Kayıp | OPEN, RESOLVED, CANCELLED, EXPIRED | OPEN → RESOLVED / CANCELLED / EXPIRED |
| Bulunan | IN_STORAGE, CLAIM_PENDING, HANDED_OVER, DISPOSED | IN_STORAGE ⇄ CLAIM_PENDING → HANDED_OVER; IN_STORAGE → DISPOSED |
| Talep | PENDING, APPROVED, REJECTED, CANCELLED | PENDING → APPROVED / REJECTED / CANCELLED |
| Eşleşme | SUGGESTED, CONFIRMED, DISMISSED | SUGGESTED → CONFIRMED / DISMISSED |

## 7. Eşleştirme puanı (toplam 100, eşik 50)

Kategori 25 · Konum 20 · Renk 15 · Marka 15 · Tarih 15 · Açıklama 10.
Ayrıntı: `calculate_match_score()` (V5). Doğruluk testi: `docs/matching-test.md` (20 çiftte 19 doğru).