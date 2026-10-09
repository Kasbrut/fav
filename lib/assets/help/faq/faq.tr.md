# SSS

## Tek cümleyle VPN nedir?

VPN, cihazınızla bir sunucu arasındaki bir tüneldir: cihazınızın trafiği sunucudan geliyormuş gibi görünür ve cihazınızla sunucu arasındaki bağlantı şifrelenir.

## Neden kendi sunucuma ihtiyacım var?

VPN sunucusunu ve yapılandırmasını siz yönetirsiniz. Ağ meta verilerini görebilen barındırma sağlayıcısına ve sunucu yöneticilerine yine de güvenmeniz gerekir. Kendi VPN’inizi çalıştırmak sizi anonim yapmaz.

## İşletmesi ne kadara mal olur?

FAV ücretsizdir. Barındırma ve trafik ücretleri sağlayıcıya ve plana bağlıdır; güncel fiyatları ve sınırları kontrol edin.

## Uygulamaya yazdığım parola cihazımda saklanıyor mu?

Oturum açma ve sudo parolaları gerektiğinde istenir ve uygulama verisi olarak kaydedilmez. SSH anahtarı, sıkılaştırma kapalı olsa bile kurulum sırasında oluşturulur ve güvenli depolamada tutulur.

## Sunucumu başka bir cihaza taşıyabilir miyim?

Evet. Parolayla şifrelenmiş bir `.favbackup` dosyası oluşturmak için Ayarlar → Yedekleme ve geri yükleme bölümünü açın. Dosyayı yalnızca boş bir FAV kurulumuna geri yükleyin ve aynı sunucuları iki cihazdan eşzamanlı yönetmeyin. Eski cihaz kaybolduysa veya ele geçirildiyse FAV, SSH anahtarlarını değiştirebilir ve iki onaydan sonra erişilebilen sunuculardaki tüm mevcut eşleri iptal edebilir.

## Uygulama cihazımı otomatik olarak VPN üzerinden geçirebilir mi?

Henüz değil. Bugün uygulama sunucuyu kurar — cihazınız resmi WireGuard uygulaması aracılığıyla bağlanır. İstemciyi bu uygulamanın içine yerleştirmek uzun vadeli yol haritasındadır.

## "Sıkılaştırmayı etkinleştir" ne yapar?

Sıkılaştırma (Gelişmiş seçeneklerde, varsayılan olarak kapalı) kurulumdan sonra tüm sunucuyu kilitler: parola ile SSH girişini kapatır (yalnızca anahtarla giriş), root SSH girişini devre dışı bırakır ve kaba kuvvet koruması ekler. Uygulamanın sunucuyu yönettiği kullanıcıya uygulanır — root girişinde oluşturduğu kullanıcıya ya da root olmayan sudo girişinde mevcut kullanıcınıza. Uygulama önce anahtar tabanlı girişinizin çalıştığını doğrular ve bir sorun olursa her şeyi otomatik geri alır, ancak yine de geri dönüş yolu olarak sağlayıcınızın konsolunu hazır bulundurun.

## Bir sunucuyu nasıl kaldırırım?

Sunucular'da bir sunucuyu kaydırın, menüsünü kullanın veya ayrıntılarında Sunucuyu kaldır'ı seçin. FAV unutmadan önce uzaktan temizlik yapmak için **VPN ve hizmetleri kaldır** seçeneğini işaretleyin; uygunsa SSH sıkılaştırmasını da geri alabilirsiniz. Seçeneği kapalı bırakıp **FAV bağlantısını kes ve kaldır**ı seçerseniz yalnızca FAV'ın SSH anahtarı uzaktan silinir ve VPN çalışmaya devam eder. **Sunucuya bağlanmadan unut** yalnızca yerel verileri siler; FAV SSH anahtarı dâhil tüm uzak değişiklikleri bırakır. Bunu yalnızca sunucuya ulaşılamıyorsa veya temizliği kendiniz yapacaksanız kullanın. Başarısız uzak adımları yalnızca yerel kaldırmadan önce yeniden deneyebilirsiniz.

## Sorun yaşıyorum — ne yapmalıyım?

Kırmızı bir hata gördüyseniz bu Yardım sekmesindeki **Hata kodları** bölümüne bakın. Hâlâ bir çözüm bulamıyorsanız, önceden doldurulmuş bir GitHub issue açmak için **Sorun bildir**'i kullanın.

## IPv6 ve profil güvenliği

Yeni v2 profilleri IPv4 ve IPv6 varsayılan rotalarını içerir; FAV'da IPv6 atlama ayarı yoktur. Yönlendirilmiş IPv6 yalnızca sağlayıcının devrettiği `/64` için dönüş yolu doğrulandıktan sonra kullanılır. Aksi halde engellenen mod, IPv6'yı ULA tünelinde yakalar ve doğrudan IPv6 kullanmak yerine sunucuda reddeder. Genel bir IPv6 endpoint'i bu kanıt değildir.

FAV yalnızca sunucu sonucunu ve üretilen profili doğrular. Dışa aktarma, bildirilen içe aktarma ve WireGuard handshake'i hedef istemcinin rotalarını veya kill switch'ini doğrulamaz; VPN durduktan sonra trafiği de korumaz. İstemci/OS korumasını ayrı yapılandırıp doğrulayın. Android'de hedef cihazdaki Always-on VPN ve VPN olmadan bağlantıları engelle ayarlarını kontrol edin; FAV kullanılabilirliklerini veya davranışlarını doğrulamadı. Ayrı bir sunucu kullanın ve konsol erişimini koruyun. QR kodları ve .conf dosyaları özel anahtarlar içerir: yalnızca hedef cihazla paylaşın.
