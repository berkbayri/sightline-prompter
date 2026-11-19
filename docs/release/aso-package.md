# Sightline ASO paketi

> DÜZELTME 2026-11-19: uygulama adı `Sightline Prompter` olarak KALIR, aşağıdaki ad/alt başlık önerileri uygulanmadı. Yalnızca görseller, en-US anahtar kelimeleri ve sürüm notları işlendi.

Tarih: 2026-11-19. Görseller: `docs/release/screenshots/proposal-v3/` (`_overview.png` tek bakışta tüm set).
Rekabet verisi Perplexity taramasından (App Store sayfaları, Kasım 2026). Anahtar kelime hacmi ve zorluğu **doğrulanmadı**; aşağıdaki seçimler listeleme metnine dayanan akıl yürütmedir.

## 1. Rekabet özeti

| Uygulama | Alt başlık | Fiyat | Not |
|---|---|---|---|
| Teleprompter Premium | Cue cards, never memorize | $3.99/ay, $19.99/yıl | Ücretsiz: 10 sn, 720p. Ses takibi yok |
| Teleprompter Premium+ | Autocue Prompter for Video | $8.99/ay, $179 ömür boyu | iPhone+Mac+iCloud+ses takibi var (bizim ana paketimiz) |
| PromptSmart Pro | Voice-Activated Prompter App | $29.99 + isteğe bağlı abonelik | VoiceTrack, yalnız İngilizce |
| BIGVU | AI Photo to Video & Subtitles | $24.99/ay, $139.99/yıl | DualShot: tek çekimden 16:9 ve 9:16 (çekim sonrası) |
| EyePrompt | Eye Contact Video Prompter | $39.99/yıl, $99.99 ömür boyu | Cihazlar arası senkron yok |
| Teleprompter.com | Smart Video Prompter Prompt | $89.99/yıl'dan | Çekim sonrası yeniden boyutlandırma |
| Parrot | (yok) | Ücretsiz | Yalnız metin gösterir, kayıt yok |
| Elgato Virtual Prompter | App Store'da yok | $2.99/ay | Mac/Windows, iPhone değil |

**Sonuç:** "Sesi takip eden teleprompter + iPhone + Mac + iCloud" tek başına benzersiz değil (Premium+ hepsini iddia ediyor). Boş görünen alan: **yatay çekerken canlı 9:16 kırpma kılavuzu**. BIGVU, Teleprompter.com ve EyePrompt bunu çekim sonrası ya da inceleme ekranında yapıyor, çekim sırasında canlı kılavuz olarak bulamadım. Bunu "hiçbir rakipte yok" diye yazmayın, yalnızca bulamadığımı söylüyorum.
İkinci fark: ücretsiz katman (2 dk, 1080p, 3 dil) rakiplerin ücretsiz sınırlarından cömert. Üçüncü: Pro fiyatı (yıllık $29.99, ömür boyu $59.99) orta aralıkta.

## 2. Metadata önerisi (en-US)

| Alan | Öneri | Uzunluk |
|---|---|---|
| Ad | `Sightline Teleprompter` | 22/30 |
| Alt başlık | `Voice Follow & 9:16 Crop Guide` | 30/30 |
| Promosyon metni | `Free to start. Your script follows your voice, the text sits under your lens, and a live 9:16 guide lets you shoot landscape and crop vertical. iPhone and Mac.` | 159/170 |
| Anahtar kelimeler | `autocue,prompter,scroll,script,speech,camera,video,record,creator,landscape,portrait,icloud,mac` | 95/100 |

Gerekçe:
- "Teleprompter" tüm rakiplerin başlığında; başlıkta olmadan aramada görünmek zor. Eski ad "Sightline Prompter" bu kelimeyi içermiyordu (`prompter` ve `teleprompter` ayrı jeton). Marka "Sightline" korunuyor.
- Alt başlık ayrı iki arama niyetini tek satıra sığdırıyor: ses takibi (rakiplerle ortak) + 9:16 kılavuz (bizim farkımız).
- Anahtar alanda ad ve alt başlıktaki kelimeler (sightline, teleprompter, voice, follow, crop, guide) tekrar edilmedi. `prompter` eski adla aramak isteyenler için eklendi.
- Ad değişikliği bir sürümle gider; Apple'ın ad kuralları ve marka tutarlılığı için sürüm notunda belirtmeye gerek yok.

## 3. Türkçe (tr)

| Alan | Öneri | Uzunluk |
|---|---|---|
| Alt başlık | `Sesi Takip Eden 9:16 Prompter` | 29/30 |
| Anahtar kelimeler | `autocue,okuma,metin,senaryo,kamera,video,kayıt,sunucu,vlog,içerik,yatay,dikey,icloud,mac` | 88/100 |

Not: Türkçe kelimelerin gerçek arama hacmini ölçmedim. Önce en-US yayınlayıp Apple Search Ads / App Store Connect analitiğinden gören terimlerle tr'yi sonra güncelleyin.

## 4. Ekran görüntüleri (8 adet, v3: `docs/release/screenshots/proposal-v3/`, tek bakış `_overview.png`)

Tasarım dili: koyu zemin, marka sarısı ışık, **Avenir Next Condensed Heavy** büyük harf başlık (tek vurgu kelimesi sarı), sarı çerçeveli özellik etiketleri, cihaz alttan taşar. Fiyat, Debug ve Pro kilidi yok.

| # | Yön | Başlık | Alt metin | Anlattığı özellik |
|---|---|---|---|---|
| 1 | Dikey | SPEAK. **IT SCROLLS.** | The teleprompter that follows your voice. Scrolls at your pace, pauses when you do. | Ses takibi |
| 2 | **Yatay** | SHOOT WIDE. **CROP TALL.** | A live 9:16 guide with rule-of-thirds lines, right in the viewfinder. | Canlı 9:16 kılavuz, üçte bir, seviye çizgisi |
| 3 | Dikey | LOOK AT THE **LENS.** | Your script sits right under the camera, so your eyes never leave the viewer. | Göz teması, dikey/yatay, ön+arka kamera |
| 4 | **Yatay** | LANDSCAPE **OR** PORTRAIT. | The prompter adapts to the way you shoot. | Yönden bağımsız, zoom, mono ses |
| 5 | Dikey (grafik) | SPEAK ANY **LANGUAGE.** | 31 languages. Many recognize speech on your device, no connection needed. | 31 dil, cihaz içi tanıma |
| 6 | Dikey (Mac+iPhone) | WRITE ON MAC. **RECORD ON IPHONE.** | Scripts sync through iCloud. Import Word, PDF, Markdown, RTF and more. | iCloud, Mac uygulaması, içe aktarma |
| 7 | Dikey | TUNE IT TO **YOUR EYES.** | Size, spacing, speed, microphone. Add [[delivery cues]] you see but never read. | Yazı/satır/harf aralığı, hız, mikrofon, kıyaslama ipuçları |
| 8 | Dikey (grafik) | STUDIO **QUALITY.** | Record straight to Photos in the quality your channel deserves. | 4K 60 fps, HDR, ProRes, HEVC/H.264 ("Available with Sightline Pro" notu var) |

Sıra mantığı: ilk üç görsel arama sonucunda görünür: ana vaat, bizim farkımız (yatay kırpma), göz teması.
Pro'ya özel özellikler (4K 60, HDR, ProRes) yalnızca 8. görselde ve "Available with Sightline Pro" notuyla gösteriliyor (Apple 2.3.2: ek satın alma gerektiren özellik açıkça belirtilmeli).
Görsellerdeki kişiler yapay zekâ ile üretildi, gerçek kişi değil; uygulama ekranları gerçek (Apple 2.3.3).
Ekran görüntüsü metninin aramada indekslenmesi tartışmalı; asıl amaç dönüşüm. Yayından sonra **Product Page Optimization** ile 1. görsel A/B test edilmeli (B: "SHOOT WIDE. CROP TALL." başa alınır).

## 5. Roast (kendi işime)

1. **Önceki set zayıftı.** Sahte elips yüz, Pro/fiyat ekranı, içinde Debug anahtarı çıkabilen ayar ekranı, ve yatay çekim (en güçlü farkımız) hiç yoktu. Bunu ben yaptım, siz fark etmeden mağazaya yükledim.
2. **"The teleprompter that listens" ve "Eyes on the lens" jenerik.** Rakiplerin hepsi "voice" diyor; sadece buna yaslanmak bizi 8. sıradaki aynı uygulama yapıyordu.
3. **Önceki v2 tipografisi de zayıftı** (ince beyaz başlık, mavi düz zemin, tek vurgu yok); v3'te baştan yapıldı. Önceki alt metin gri ve küçüktü, arama sonucunda okunmazdı. Bu sette büyütüldü; yine de küçük cihazlarda gerçek telefonda kontrol edilmeli.
4. **Hâlâ zayıf noktalar:** (a) 5. görsel (betik listesi) siyah ve boş, en az ikna edici ekran; (b) 6. görsel ayar listesi, ekran görüntüsü olarak sıkıcı; (c) hepsinde aynı "Hi everyone…" metni var; (d) kamera karesi 1536 px üretim, yatay görsellerde hafif yumuşak; (e) sosyal kanıt, puan, "X kişi kullanıyor" yok, çünkü yok.
5. **Doğrulanmamış varsayımlar:** anahtar kelime hacmi, "voice follow" vs "voice-activated" tercihi, ad değişikliğinin marka aramasına etkisi. Hepsi akıl yürütme.
6. **Süreç hatalarım:** yatay görselleri bitirmeden eksik seti App Store'a yükledim; mono kayıt hatası yüzünden bir kaydınızı kaybettirdim (düzeltildi); build 5'i, ekran görüntüsü ve metadata kararı bitmeden yükledim.
7. **Ad değişikliği riski:** "Sightline Prompter" adıyla mevcut kullanıcılar ve marka aramaları var. Eşleşme kaybı küçük ama sıfır değil; geri alınabilir (ad her sürümle değişir).

## 6. Mağazaya göndermeden önce (sizin kararınız)

1. Görselleri onayla (`proposal-v3/`).
2. Ad/alt başlık/anahtar kelimeler/promosyon metnini onayla (açıklama metnindeki "never" ve fiyat cümleleri sürüm 1.0.2 açıklamasında kalır; açıklama ASO'ya dahil değil).
3. Onayla birlikte: görselleri iki yerele yükle, metadata'yı 1.0.2'ye işle, iki sürümü incelemeye gönder.
4. Yayından sonra: Product Page Optimization ile 1. görsel testi; Custom Product Page: "9:16 kırpma" reklamı için ayrı sayfa.


## 7. Mac görselleri

Görseller: `docs/release/screenshots/proposal-mac-v3/` (2880x1800, Mac App Store 16:10; `_overview.png` tek bakış; üreten betik `frame-mac.swift`, ham kayıtlar `raw/`). Eski Mac görselleri `archive-old/mac-old/` altında. Uygulama ekranları gerçek Mac uygulamasından alındı (SIGHTLINE_DEV derlemesi, geçici kitaplık klasörü, uydurma "Q4 product update" metinleri). Fiyat, Debug ve kilit görünmüyor; Pro'ya özel iki görselde "Available with Sightline Pro" notu var.

| # | Dosya | Başlık | Alt metin | Anlattığı özellik |
|---|---|---|---|---|
| 1 | `1-notch.png` | TELEPROMPTER UNDER THE NOTCH. | Your script sits right below the camera, so your eyes never leave the lens. | Çentik altındaki panel (NotchPanel), vurgulanan kelime, `[[ipucu]]` gösterimi, arkada kitaplık penceresi |
| 2 | `2-present.png` | PRESENT WITH CONFIDENCE. | Look at your audience on every video call, keynote and recording. | Toplantı/sunum kullanımı; AI üretimi fotogerçekçi sahne (video görüşme ızgarası, kamera altında panel) |
| 3 | `3-hidden.png` | INVISIBLE TO EVERYONE ELSE. | Hide the prompter from screen sharing and recording. Only you see your script. | Ekran paylaşımı/kaydından gizleme (`NotchPanel.sharingType`); sol "YOU SEE", sağ "THEY SEE" |
| 4 | `4-languages.png` | SPEAK ANY LANGUAGE. | Voice following in 31 languages, many of them on-device. | Ses takibi, 31 dil. Not: "Available with Sightline Pro" |
| 5 | `5-sync.png` | WRITE ON MAC. RECORD ON IPHONE. | Scripts sync through iCloud. Import Word, PDF, Markdown and more. | iCloud senkron, Word/PDF/Markdown/RTF/HTML/ODT içe aktarma, `[[teslim ipuçları]]` |
| 6 | `6-pace.png` | DIAL IN YOUR PACE. | Live words per minute and time left. Drive it with a DualSense controller. | Dakikada kelime göstergesi, DualSense kumanda ayarları. Not: "Available with Sightline Pro" |

AI sahneler (Figma, gpt-image-2.5-flare, 3 görsel, `raw/`): `scene1.png` 2. görselde kullanıldı; `scene2.png` ve `scene3.png` kullanılmadı, yedek. Sahnelerde okunur metin yok; kamera çentiği altındaki panel yalnızca soyut çizgilerden ve tek sarı vurgudan oluşur. Kişiler gerçek değil, markasız. Yayından önce gözle gözden geçirin (yapay üretim eller/yüz kusurları olabilir; App Store inceleme kuralları açısından "illüstrasyon" kabul edilip edilmeyeceğini doğrulamadım).

Dürüst notlar: 6. görseldeki "148 WPM / 2:14 LEFT" gösterge biçimini örnekler, ölçülmüş değer değildir. 3. görseldeki "THEY SEE" tarafı çizimdir (yer tutucu bloklar), gerçek bir paylaşım yakalaması değil. Gizlemenin Zoom, Meet, Teams gibi uygulamalarda gerçekten çalıştığı test edilmedi; yalnızca `sharingType = .none` kodda var.

### Mac metadata önerisi (en-US)

| Alan | Öneri | Uzunluk |
|---|---|---|
| Ad | `Sightline Teleprompter` (iPhone ile aynı) | 22/30 |
| Alt başlık | `Notch Prompter for Video Calls` | 30/30 |
| Promosyon metni | `Free to start. Your script sits under the notch, follows your voice, and stays hidden from screen sharing. Syncs with iPhone through iCloud.` | 140/170 |
| Anahtar kelimeler | `autocue,presenter,keynote,webinar,meeting,speaker,script,speech,voice,camera,screen,icloud,iphone` | 97/100 |

Gerekçe: alt başlık Mac'e özgü iki niyeti taşır (çentik, görüntülü görüşme). Anahtar alanda ad ve alt başlıktaki kelimeler (sightline, teleprompter, notch, prompter, video, calls) tekrar edilmedi. Zoom, Teams, Meet gibi marka adları bilerek yazılmadı. Anahtar kelime hacmi ve zorluğu doğrulanmadı.
