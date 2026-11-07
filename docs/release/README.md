# App Store'a çıkış rehberi: Sightline Prompter (iPhone + Mac)

Bu rehber, ilk kez App Store'a uygulama gönderen biri için yazıldı. Her adımın başında kimin yapacağı yazıyor:

- **[SEN]** Apple hesabında veya cihazında senin yapman gereken şey. Ben yapamam.
- **[BEN]** Claude'a "şunu yap" dediğinde yapacağım şey.
- **[KARAR]** Senin vermen gereken karar. Önerimi yazdım, değiştirebilirsin.

**Güncel durum:** satış modeli ve fiyatlar kararlaştırıldı, Pro kodu (satın alma, paywall, ücretsiz sınırlar) iPhone ve Mac'e yazıldı, ekran görüntüleri hazır (`screenshots/`). Geriye hesap onayı, Apple tarafındaki işler ve uygulama adı kontrolü kaldı.

Hazır olan her şey bu klasörde: `pricing.md` (fiyat ve abonelik önerisi), `store-listing.md` (mağaza metinleri, kopyala-yapıştır).

---

## Önce büyük resim

Tek bir **App Store Connect uygulama kaydı** açacaksın. Hem iPhone hem Mac sürümü aynı kayıtta, aynı **bundle ID** ile (`com.berkbayri.SightlinePrompter`) yayınlanır. Buna **universal purchase** denir: biri satın alırsa iki cihazda da kullanır. Ayrı ayrı yayınlamak da mümkün ama önermem, çünkü satın alma iki kez gerekir ve karışıklık yaratır.

Süreç şöyle akar:

1. Hesap onayı gelir, ödeme/vergi bilgilerini girersin.
2. Sertifikaları ve uygulama kaydını oluştururuz.
3. iPhone derlemesini ve Mac paketini yükleriz.
4. **TestFlight** ile kendi cihazlarında dener, istersen birkaç arkadaşa verirsin.
5. Mağaza sayfasını doldurur, incelemeye gönderirsin.
6. Apple inceler (çoğu uygulama 1-2 gün içinde sonuç alır). Onaylanınca yayına alırsın.

Hesap "pending" durumundayken **1. adımdan öncesini** hazırlayabilirsin. Aşağıda "Şimdi yapılabilecekler" bölümü bunu listeliyor.

---

## Bu oturumda sizin için hazırlananlar

| Ne | Nerede | Neden gerekli |
|---|---|---|
| Gizlilik manifestosu (iPhone + Mac) | `iOS/Resources/PrivacyInfo.xcprivacy`, `macOS/Resources/PrivacyInfo.xcprivacy` | Apple, uygulamanın hangi sistem API'lerini kullandığını bildirmeni ister |
| Mac sandbox yetkileri | `macOS/Resources/SightlinePrompter.entitlements` | Mac App Store'da **App Sandbox zorunlu**; mikrofon, ağ (konuşma tanıma için) ve kullanıcının seçtiği dosyalar için izinler |
| Mac App Store paketi betiği | `macOS/appstore.sh` | Evrensel (Apple Silicon + Intel) derler, imzalar, `.pkg` üretir. İmza bilgisi olmadan da çalışır, sadece kontrol eder |
| Uygulama kategorisi | iPhone ve Mac Info.plist | Mağaza kategorisi: Video |
| Gizlilik politikası sayfası | `docs/privacy.html` | App Store Connect, bir **Gizlilik Politikası URL'si** ister. GitHub Pages'e çıkınca adres: `https://berkbayri.github.io/sightline-prompter/privacy.html` |
| Fiyat ve abonelik önerisi | `pricing.md` | Rakipler, rakamlar, öneri |
| Mağaza metinleri | `store-listing.md` | İsim, alt başlık, açıklama, anahtar kelimeler, inceleme notları |
| Kurulan skill'ler | `~/.claude/skills` altında `asc-*`, `paywalls` | App Store Connect komutları, derleme/yükleme, bölgesel fiyat, paywall tasarımı |

Doğrulananlar: Mac paketi evrensel derleniyor ve yalnızca sistem kütüphanelerine bağlanıyor; iPhone paketi ikon ve gizlilik manifestosunu içeriyor.

---

## Şimdi yapılabilecekler (hesap onayı beklenmeden)

1. **[KARAR] Satış modelini seç.** `pricing.md` dosyasını oku, "Karar 1-4" bölümüne bak. Önerim: ücretsiz indirme + Pro (yıllık / aylık / ömür boyu).
2. **[SEN] Uygulama adının boş olduğunu kontrol et.** App Store'da her isim tekildir. Onaydan sonra App Store Connect'te "Sightline Prompter" yazınca alınmışsa hata verir. Alternatifler `store-listing.md`'de.
3. ~~Ekran görüntüleri~~ **[BEN] Hazır:** `docs/release/screenshots/`. iPhone 6,9" (1320×2868) 3 adet, Mac (2880×1800) 3 adet. iPhone görüntüleri simülatörde, kamera önizlemesi yerine örnek bir görselle üretildi; mağazada "örnek görüntü" olarak kabul edilir, ama istersen gerçek telefon görüntülerinle değiştir. Eski talimat (isteğe bağlı, gerçek ekran için):
   - iPhone: 6,9" ekran. iPhone 16 Pro'nun ekran görüntüsü (1206×2622) kabul ediliyor. En az 3, en fazla 10 adet. Öneri: script listesi, dikey kayıt ekranı, yatay kayıt ekranı, ayarlar.
   - Mac: 2880×1800 (veya 1440×900, 2560×1600). Notch'taki paneli gösteren 3 görüntü.
   - Telefondan almak için ses yukarı + yan düğme. Mac'te Cmd+Shift+5.
4. **[SEN] Gizlilik politikasını yayında gör.** Bu değişiklikler GitHub'a push'lanınca sayfa birkaç dakikada yayınlanır. Adresi tarayıcıda aç ve çalıştığını doğrula.
5. **[SEN] Apple hesabında 2 adımlı doğrulama açık olsun.** Zorunlu.
6. **[SEN] Satıcı bilgisini düşün.** Bireysel hesapta **yasal adın** mağazada satıcı olarak görünür. Şirket adı istiyorsan kuruluş hesabı gerekir (D-U-N-S numarası ister, daha uzun sürer). Hesabın zaten başvuruda; bunu şimdi değiştiremezsin, ama bilmen gerekir.
7. **[SEN] AB "trader" durumunu düşün.** Ücretli uygulama sattığın için Apple seni büyük ihtimalle AB'de **trader (ticari satıcı)** sayacak. Bu durumda adresin, telefonun ve e-postan AB mağaza sayfalarında **herkese açık** görünür. Ev adresin yerine bir posta kutusu (PO box) veya iş adresi kullanabilirsin. Bunu şimdiden planla.

---

## Hesap onaylandıktan sonra: adım adım

### Adım 1. Ödeme ve vergi (yalnızca ücretli satış için) **[SEN]**

App Store Connect → **Business** (İş) → **Agreements** (Sözleşmeler):

1. **Paid Apps Agreement**'ı kabul et. Bunu yalnızca **Account Holder** (hesap sahibi) yapabilir; bireysel hesapta sensin.
2. **Banka hesabı** ekle (IBAN, SWIFT).
3. **Vergi formunu** doldur. Türkiye'de yaşayan biri için Apple, **W-8BEN** isteyecek. Sorulara dürüstçe cevap ver; Türkiye-ABD vergi anlaşması için vergi kimlik numaranı (TCKN/VKN) gir.
4. Türkiye için ek vergi/KDV bilgisi sorarsa mali müşavirine danış.

Ücretsiz bir uygulama yayınlıyorsan bu adımı atlayabilirsin, ama sonradan abonelik eklemek için gerekecek.

### Adım 2. Small Business Program'a başvur **[SEN]** **[KARAR: evet]**

Apple normalde %30 komisyon alır. Yıllık geliri 1 milyon dolardan az geliştiriciler için bu **%15** olur. Otomatik değil, başvuru gerekir: <https://developer.apple.com/app-store/small-business-program/>. İlk satıştan önce yap.

### Adım 3. Takım kimliğini ve sertifikaları hazırla **[SEN] + [BEN]**

1. <https://developer.apple.com/account> → **Membership details**: **Team ID**'ni kopyala (10 karakter). Bana ver.
2. Mac'te Xcode → Settings → **Accounts** → Apple kimliğini ekle → takımını seç → **Manage Certificates** → **+**:
   - **Apple Distribution**
   - **Mac Installer Distribution** (Mac için)
   (iPhone'daki mevcut "Apple Development" sertifikan geliştirme içindir, mağaza için yetmez.)
3. Terminalde doğrula: `security find-identity -v -p codesigning`. İki yeni satır görmelisin.

### Adım 4. Uygulama kimliğini kaydet **[SEN]**

developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → **+** → **App IDs** → **App**:

- Description: Sightline Prompter
- Bundle ID: **Explicit**, `com.berkbayri.SightlinePrompter`
- Capabilities: şimdilik **hiçbirini** seçme. (iCloud Drive senkronu eklersek sonra ekleriz.)

### Adım 5. App Store Connect'te uygulamayı oluştur **[SEN]**

appstoreconnect.apple.com → **Apps** → **+** → **New App**:

- Platforms: **iOS** ve **macOS** (ikisini işaretle)
- Name: `Sightline Prompter` (30 karakter sınırı)
- Primary Language: English (U.S.)
- Bundle ID: listeden seç
- SKU: `sightline-prompter-001` (sadece senin görebileceğin iç kod)
- User Access: Full Access

### Adım 6. Mac için profil oluştur **[SEN]**

Certificates, Identifiers & Profiles → **Profiles** → **+** → **Mac App Store Connect** → App ID'yi seç → **Apple Distribution** sertifikanı seç → ad ver → indir (`.provisionprofile`). Dosyayı `~/Downloads`'ta bırak, yolunu bana söyle.

(iPhone için profili Xcode otomatik yönetir.)

### Adım 7. iPhone derlemesini yükle **[BEN] + [SEN]**

Ben: `iOS/project.yml` içine takım kimliğini yazar, sürüm/derleme numarasını ayarlar, arşivler. Sen: Xcode'da **Product → Archive → Distribute App → App Store Connect → Upload**. İstersen ben komut satırından da yapabilirim (`xcodebuild archive` + `exportArchive`).

Her yüklemede **derleme numarası (build)** bir öncekinden büyük olmalı.

### Adım 8. Mac paketini yükle **[BEN] + [SEN]**

Ben `macOS/appstore.sh` komutunu imza bilgileriyle çalıştırırım, `.pkg` çıkar. Sen **Transporter** uygulamasını (Mac App Store'dan ücretsiz) aç, `.pkg`'yi sürükle, **Deliver**'a bas.

> **Önemli, Mac sandbox'ı:** Mac App Store sürümü kum havuzunda (sandbox) çalışır. Ev dizinindeki iCloud Drive klasörüne doğrudan erişemez; kütüphane uygulamanın kendi klasörüne yazılır. Kod buna şimdiden uyumlu çalışıyor (iCloud Drive yolu bulunamazsa kendi belgeler klasörüne geçiyor). Konuşma tanıma, DualSense ve dosya içe aktarma sandbox'ta **gerçekten denenmeli**: bunu TestFlight'ta yaparız. Sorun çıkarsa düzeltirim.

### Adım 9. TestFlight ile dene **[SEN]**

Yüklenen derleme birkaç dakika "işleniyor" der. Sonra App Store Connect → **TestFlight**:

1. **Internal Testing** grubu oluştur, kendini ekle. İncelemesiz, hemen yüklenir.
2. iPhone'da **TestFlight** uygulamasından, Mac'te de TestFlight uygulamasından kur.
3. Şunları dene: kamera, mikrofon, konuşma tanıma (Türkçe dahil), video kaydı, içe aktarma, bildirim gelince takip. Mac'te: panel, DualSense, kütüphane.
4. Bulduğun hataları bana yaz.

### Adım 10. Mağaza sayfasını doldur **[SEN]**

Her platform için ayrı ayrı (iOS ve macOS). `store-listing.md`'deki metinleri kopyala:

- Alt başlık, açıklama, anahtar kelimeler, destek URL'si, pazarlama URL'si
- **Gizlilik Politikası URL'si**: `https://berkbayri.github.io/sightline-prompter/privacy.html`
- Ekran görüntüleri
- **Kategori**: Primary: Photo & Video. Secondary: Productivity.
- **Fiyat**: Ücretsiz (abonelik kullanacaksan). Ücretli satış için `pricing.md`'ye bak.
- **Telif hakkı**: `2026 Berk Bayri`

**App Privacy (gizlilik etiketi):** "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app.** Uygulama hiçbir veriyi sunucuya göndermiyor; konuşma tanıma Apple'ın kendi çerçevesinde olur ve senin tarafından toplanmaz. (Abonelik eklenirse yine "veri toplamıyoruz" cevabı geçerli kalır; satın alma bilgisini yalnızca Apple tutar.)

**Yaş derecelendirmesi:** Tüm sorulara "None / Hayır". Sonuç 4+ olur.

**Şifreleme (export compliance):** Uygulama zaten `ITSAppUsesNonExemptEncryption = false` bildiriyor. Soru çıkarsa "uygulama yalnızca işletim sisteminin standart şifrelemesini kullanır" seçeneğini işaretle.

**Content Rights:** "Üçüncü taraf içeriği içermiyor" → Hayır.

### Adım 11. İncelemeye gönder **[SEN]**

Her platform sürümünde (1.0):

1. **Build** bölümünden yüklediğin derlemeyi seç.
2. **App Review Information**'a `store-listing.md`'deki **inceleme notlarını** yapıştır. Mac uygulaması menü çubuğunda ve notch'ta yaşıyor, Dock'ta ikonu yok; bunu mutlaka açıkla ki inceleme uzmanı uygulamayı bulabilsin.
3. Giriş bilgisi gerekmiyor (hesap yok).
4. **Release**: "Manually release this version" seç. Onaylansa bile sen düğmeye basana kadar yayınlanmaz.
5. **Add for Review → Submit for Review**.

### Adım 12. Sonuç **[SEN]**

- "Waiting for Review" → "In Review" → "Pending Developer Release" (onaylandı) veya "Rejected" (red).
- Red gelirse **panik yok**: Apple nedenini yazar. İlk gönderimlerde yaygındır. Mesajı bana yapıştır, birlikte düzeltiriz.
- "Pending Developer Release" olunca **Release This Version**'a bas. Birkaç saat içinde mağazada görünür.

---

## Sık red sebepleri (bu uygulama için)

| Risk | Ne yapıldı / yapılacak |
|---|---|
| Kamera/mikrofon izin metinleri belirsiz | Metinler açık ve gerçek amacı söylüyor |
| Mac uygulaması bulunamıyor (menü çubuğu) | İnceleme notunda anlatılıyor |
| Çökme, boş ekran | TestFlight'ta test edilecek |
| Gizlilik etiketi ile davranış uyuşmuyor | "Veri toplanmıyor"; kodda ağ/analitik yok |
| Abonelik: fiyat, süre, yenileme koşulları görünmüyor; "Satın almayı geri yükle" yok | Paywall yazılırken `paywalls` skill'i ve Apple kurallarına göre eklenecek |
| Ekran görüntüleri uygulamayı yanlış gösteriyor | Gerçek ekranlardan al |
| Eksik/boş URL'ler | Gizlilik ve destek sayfaları hazır |

---

## Lisans notu (GPL)

Depo GPL-3.0 lisanslı. Telif hakkı tek kişide (senin; git geçmişinde yalnızca sen varsın), bu yüzden kendi uygulamanı App Store'da farklı koşullarla satabilirsin. İleride **başkalarından kod kabul edersen** (pull request), onlardan telif/lisans izni (CLA) almadan bu mümkün olmayabilir. Kabul edeceksen önce bunu yaz.

Açık kaynak GitHub sürümü ücretsiz kalabilir; App Store sürümünün farkı "hazır, güncellemeli, TestFlight/iCloud destekli" olmasıdır. Birçok geliştirici bu modeli kullanır.

---

## Hesap onaylanınca bana ne diyeceksin

Şunu yaz: **"Hesabım onaylandı. Team ID: XXXXXXXXXX."** Sonra sırayla:

1. Sertifikaları oluşturunca söyle, imza adlarını doğrularım.
2. App Store Connect'te kaydı oluşturunca söyle.
3. İstersen **App Store Connect API anahtarı** oluştur (Users and Access → Integrations → Keys, "App Manager" rolü). Onu bana verirsen derleme yükleme, TestFlight, fiyat ayarı, metadata işlerini komut satırından ben yaparım (`asc` skill'leri kurulu). Anahtarı sohbete yapıştırma; dosya yolunu söyle.
