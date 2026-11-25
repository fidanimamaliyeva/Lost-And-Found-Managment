# Eşleştirme Doğruluk Testi

Tarih: 25.11.2026
Test verisi: `src/main/resources/db/seed/demo_pairs.sql`
(20 kayıp bildirimi, 20 gerçek eş, 6 tuzak kayıt; seed.sql'deki 10.000 kaydın üzerine)

## Sonuç

- 20 kayıp bildiriminin 19'unda gerçek eş ilk sırada çıktı.
- Ayrıntılı sonuçlar: `matching-test.csv`

## İlk sırada çıkmayan çiftler

- Yok

## Notlar

- En zor çift DEMO-06 (cüzdan): Tuzak kayıt konum ve tarih açısından avantajlıydı.
  Gerçek eşi açıklamadaki ortak kelimeler ("deri", "öğrenci kartı") öne geçirdi.