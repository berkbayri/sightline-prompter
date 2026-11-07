# Fiyatlandırma ve ücretli özellikler

> **Durum (7 Kasım 2026):** Karar verildi ve uygulamaya işlendi. Satış modeli: ücretsiz + Pro. Fiyatlar: aylık $4.99, yıllık $29.99 (7 gün deneme), ömür boyu $59.99. Tek hak iPhone ve Mac'te geçerli. Aşağıdaki kod tarafı bitti; App Store Connect'te ürünleri tanımlamak hesap onayından sonra yapılacak (`README.md`, Adım 9).

### Uygulamada ne var

| Ürün | Product ID |
|---|---|
| Pro Yıllık (7 gün deneme) | `com.berkbayri.SightlinePrompter.pro.yearly` |
| Pro Aylık | `com.berkbayri.SightlinePrompter.pro.monthly` |
| Pro Ömür Boyu | `com.berkbayri.SightlinePrompter.pro.lifetime` |

Abonelik grubu adı: **Sightline Pro**. ID'ler App Store Connect'te **birebir** aynı yazılmalı.

Ücretsiz sürümde uygulanan sınırlar (koddaki karşılığı: `Shared/Core/FreeTier.swift`):

- Sesle takip: bir çalıştırmada **2 dakika**, yalnızca **İngilizce, Türkçe, İspanyolca**.
- iPhone video: **1080p, en fazla 30 fps, 16:9, HEVC/H.264, 2 dakika**. 4K, 60 fps, HDR, ProRes, 4:3, görüntü sabitleme ve pozlama/odak kilitleri Pro.
- Prompter alanının genişlik/yükseklik ayarı, hız göstergesi (kelime/dk), DualSense kontrolü: Pro.
- Sınırsız script, içe aktarma, düzenleme, el ile kaydırma: ücretsiz.

Notlar: Sesle takip süresi her başlatışta yeniden sayılır; bu, süreyi sıfırlamak için kapatıp açmayı mümkün kılar. İlk sürüm için bilerek basit tutuldu. İstismar çoğalırsa günlük toplam süreye çevrilir.

Test için: Xcode'dan çalıştırınca `Sightline.storekit` dosyası devreye girer ve sahte satın alma yapabilirsin. Telefona kurduğum geliştirme sürümünde Ayarlar'da **"Debug: act as Pro"** anahtarı var; Pro özelliklerini mağaza olmadan denemek içindir. Mağaza sürümünde bu anahtar yok.

Araştırma tarihi: 7 Kasım 2026. Rakam kaynakları: App Store sayfaları, RevenueCat "State of Subscription Apps 2026", Apple geliştirici belgeleri. Rakamlar bölgeye ve zamana göre değişir, bunları **başlangıç noktası** say.

## Rakipler (ABD App Store)

| Uygulama | Aylık | Yıllık | Tek seferlik | Ücretsiz kısım |
|---|---:|---:|---:|---|
| Teleprompter Pro (Premium) | ~$7-8 | $59.99 | $159.99 | Sınırsız script ve kaydırma. Kayıt ve içe aktarma ücretli |
| Teleprompter Premium (diğeri) | $3.99 | $19.99 | | 10 saniyelik kayıt, 720p |
| PromptSmart Pro | $3.99 (opsiyonel) | $34.99 | **$29.99** | Satın alınca ses takibi dahil |
| PromptSmart+ | $8.99 | $79.99 | | Ses takibi için abonelik/deneme |
| Moody (iPhone) | $9.99 | $59.99 | $149.99 | İlk 10 kayıt |
| Moody (Mac, notch) | | | **$19.99** (kendi sitesinde) | |
| CueNotch (Mac) | | | **$29.99** | Günde 3 kullanım, 100 kelime |
| BIGVU | $24.99 | $89-139 | | 9 dk, 720p, filigranlı |
| Prezenter | | | $0.99 | 1 script, 30 sn kayıt |
| iA Presenter | $7.99 | $39.99 | Mac $49.99 | 7 gün deneme |

**Okuma:**

- Düz kaydırmalı prompter artık **ücretsiz bir ürün** (Parrot ücretsiz). Para, **sesle kelime takibi + video kaydı + çoklu dil** gibi daha değerli özelliklerden kazanılıyor.
- Mac notch prompter'lar çoğunlukla **tek seferlik $19.99-29.99**. Aboneliğe karşı tepki var.
- iPhone video prompter'larında yıllık $20-60 aralığı yaygın.
- Senin avantajın: iPhone kayıt + Mac notch + 31 dil + gamepad **tek hak ile**. Kimse ikisini birden sunmuyor.

## Benchmark (RevenueCat 2026)

- İndirenlerin yaklaşık **%2'si** 35 gün içinde ödeme yapar (freemium medyanı).
- Yardımcı uygulamalarda ilk yıllık yenileme oranı **%35**, aylık ilk yenileme **%57**.
- Deneme süresi **5-9 gün** olanlarda denemeden ödemeye geçiş ~%37, 17-32 gün olanlarda ~%42 (ilişki, neden-sonuç değil).
- Küçük bir uygulama için gerçekçi hedef: 1.000 indirme → ~20 ödeyen.

## Hangi özellik ücretli olmalı?

Prensip: **Ücretsiz kısım gerçekten işe yarasın** ("1 dakikada fikri anlasınlar") ama **asıl değer ücretliye** bağlansın. Ses takibi işlemciyi kendi cihazında çalıştırdığın için senin sunucu maliyetin yok. Bu, aboneliği "devam eden maliyet" ile savunmayı zorlaştırır; Apple da aboneliğin **sürekli değer** sunmasını ister. Bu yüzden **ömür boyu seçeneği** burada önemli.

| Özellik | Ücretsiz | Pro |
|---|:---:|:---:|
| Script oluşturma, içe aktarma, düzenleme, sınırsız script | ✔ | ✔ |
| Manuel kaydırma, el ile okuma | ✔ | ✔ |
| **Sesle takip** | Oturum başına **2 dakika** | Sınırsız |
| **Video kayıt** | 1080p, **2 dakikaya kadar** | **4K, 60 fps, HDR, ProRes**, sınırsız süre |
| 16:9 / 4:3, codec, stabilizasyon, pozlama kilidi | | ✔ |
| Prompter alanı genişlik/yükseklik ayarı | | ✔ |
| 31 dil | 3 dil (örn. İngilizce, Türkçe, +1) | Hepsi |
| Mac notch paneli | ✔ (manuel) | ✔ sesle takip dahil |
| DualSense kontrol | | ✔ |
| Hız göstergesi (kelime/dk, kalan süre) | | ✔ |

Bu dağılım, "indir, dene, beğen, aç" akışına uyar. **Önemli:** ilk sürümden itibaren neyin ücretsiz olduğunu belirle. Bir özelliği sonradan ücretliye çevirmek kullanıcıyı kızdırır ve kötü yorum getirir.

## Öneri

| Plan | ABD fiyatı | Not |
|---|---:|---|
| **Pro Aylık** | **$4.99** | Yıllığı çekici gösteren bir seçenek. Çok kişi seçmeyecek |
| **Pro Yıllık** | **$29.99** | **7 gün ücretsiz deneme.** Ana plan. Aylıktan %50 ucuz |
| **Pro Ömür Boyu** | **$59.99** | Yıllığın 2 katı. Aboneliğe karşı olanlar için |

Neden bu rakamlar: bilinmeyen yeni bir marka olarak rakiplerin **altında başlamak** daha güvenli. Fiyatı sonradan yükseltmek kolay (mevcut aboneler korunur), düşürmek ise ilk izlenimi bozar. Perplexity araştırması $7.99 / $39.99 / $79.99 öneriyor; bu, rakiplerin ortalama üst bandı. Ben daha düşük, iki aşamalı bir başlangıç öneriyorum, ama ikisi de savunulabilir.

Ödeme sonrası net gelir (Small Business Program, %15 komisyon): yıllık $29.99 → yaklaşık **$25.50** (vergiden önce; bazı ülkelerde KDV/vergi ayrıca düşer).

### Türkiye fiyatı

Apple, ABD fiyatını kurla otomatik çevirir, ama abonelik fiyatları **kur değişince kendiliğinden güncellenmez**. Önce Apple'ın önerdiği Türkiye fiyatına bak, sonra elle düzelt. Başlangıç hipotezi: Türkiye fiyatları USD karşılığının **%40-60'ı** olsun. Rakip "Teleprompter+" Türkiye'de ₺1.299,99/yıl istiyor; bu yüksek. Kendi rakamını App Store Connect'te "Price preview" ile kontrol et. `asc-ppp-pricing` skill'i bölgesel fiyatları toplu ayarlar; hesap açılınca birlikte yaparız.

## Senin vermen gereken kararlar

**Karar 1. Satış modeli.** Üç seçenek:

| Seçenek | Artı | Eksi |
|---|---|---|
| **A. Ücretsiz + Pro (aylık/yıllık/ömür boyu)** *(önerim)* | En geniş kitle; üç ödeme tercihi; gelir tavanı yüksek | Yapması en fazla iş: StoreKit + paywall + sandbox test (yaklaşık 1 hafta) |
| B. Tek seferlik ücretli uygulama ($14.99-19.99) | Çok basit, abonelik riski yok | Denemeden alınmaz, indirme çok düşük olur; sonradan ücretsiz sunamazsın |
| C. Önce tamamen ücretsiz çık, sonra Pro ekle | En hızlı yayın, yorum toplar | Sonradan özellik kısıtlamak kötü yorum getirir. Yalnızca "yeni" özellikler Pro olabilir |

**Karar 2. Mac ve iPhone birlikte mi?** Önerim: **Tek Pro hakkı iki platformda** (universal purchase). Moody gibi rakipler ayrı satıyor, ama kullanıcı için en kolay olan tek ödeme.

**Karar 3. Ömür boyu sunulsun mu?** Önerim **evet**. Ses takibi cihazda çalıştığı için sürekli maliyetin yok; ömür boyu seçeneği abonelik karşıtlarını yakalar. Ücretini yıllığın 2 katı tut ($59.99) ve "tüm mevcut Pro özellikleri" olarak tanımla.

**Karar 4. Deneme süresi.** Önerim: yıllık plana **7 gün ücretsiz deneme**. Sonra 14 gün ile A/B test edilir.

## Uygulama için yapılacaklar (Karar 1 gelince)

1. StoreKit 2 ile `Pro` ürünlerini ekle: 1 abonelik grubu (aylık+yıllık), 1 non-consumable (ömür boyu).
2. Uygulamaya **paywall** ekle: fiyat, süre, yenileme koşulları, "Satın almayı geri yükle" düğmesi. Apple bunları zorunlu tutuyor. `paywalls` skill'ini kullanırım.
3. Ücretsiz sınırlar (2 dk takip, 2 dk kayıt) uygulanır.
4. Lokal StoreKit test dosyasıyla Xcode'da, sonra TestFlight'ta sandbox ile test edilir.
5. App Store Connect'te ürünler tanımlanır, her biri için inceleme ekran görüntüsü yüklenir.

Bu iş TestFlight testinden önce bitmeli, çünkü ilk incelemeye ürünlerle birlikte gönderilir.

## Aile Paylaşımı

Ömür boyu ve abonelik için **Aile Paylaşımı** açılabilir (5 aile üyesine kadar). Önerim: aç. Bu tür araçlar için rakip yok; kullanıcı mutluluğu getirir, gelir kaybı küçük.
