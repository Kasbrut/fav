# İlk sunucunuz

Adım adım bir rehber — önceden deneyim gerekmez.

## 1. Bir sanal makine edinin

Sanal makine (genellikle VPS olarak adlandırılır), bir veri merkezinde çalışan ve her zaman açık olan küçük bir bilgisayardır. Bunu Linode, DigitalOcean, Hetzner veya Vultr gibi bir bulut sağlayıcıdan aylık olarak kiralarsınız. En ucuz plan (tipik olarak 1 paylaşımlı CPU çekirdeği ve 1 GB RAM) kişisel bir [VPN](glossary://vpn) çalıştırmak için fazlasıyla yeterlidir.

Sunucuyu sipariş ederken işletim sistemi olarak Debian veya Ubuntu'nun en son kararlı sürümünü seçin. Sağlayıcının kontrol panelini kapatmadan önce üç şeyi not edin: sunucunun genel IP adresi, oturum açma kullanıcı adı (genellikle `root`) ve sağlayıcının size verdiği parola.

## 2. WireGuard portunu açın

[Firewall](glossary://firewall), sunucunuza hangi ağ bağlantılarının girip çıkmasına izin verileceğine karar veren bir filtredir. Çoğu bulut sağlayıcı varsayılan olarak bir firewall uygular ve bu firewall açıkça açmadığınız tüm portları engeller. WireGuard bir [UDP port](glossary://udp-port) üzerinden iletişim kurar — varsayılan 51820'dir — bu yüzden o port üzerinde UDP trafiğine izin veren bir gelen kuralı eklemeniz gerekir.

Her büyük sağlayıcıya özgü adım adım talimatlar için bu Yardım bölümündeki "Firewall ve port açma" girişine bakın. Her sağlayıcının kontrol paneli biraz farklı görünür, ancak adımlar aynıdır: firewall kurallarını bulun, port 51820 için bir gelen UDP kuralı ekleyin ve kaydedin.

## 3. Sunucuyu bu uygulamaya ekleyin

Sunucular'ı açıp Sunucu ekle'yi seçin. Genel IP adresini, SSH portunu (varsayılan 22), kullanıcı adını ve 1. adımdaki parolayı girin. Gelişmiş seçenekleri yalnızca WireGuard portu, alt ağ, DNS, sıkılaştırma, izleme veya yedeklemeyi değiştirmeniz gerekiyorsa açın; ardından Bağlan ve kur'u seçin.

Uygulama sunucunuza [SSH](glossary://ssh) — şifreli bir kanal — üzerinden bağlanır ve hemen sunucunun [parmak izini](glossary://fingerprint) gösterir. Parmak izi, sunucuyu benzersiz şekilde tanımlayan kısa bir koddur. Onu okuyun ve yalnızca sağlayıcınızın kontrol panelinde veya konsol çıktısında gördüğünüzle eşleşiyorsa onaylayın. Onaylandıktan sonra uygulama bunu hatırlar ve değişirse sizi uyarır — beklemediğiniz bir değişiklik bir güvenlik sorununun işareti olabilir.

## 4. Kurulumu bekleyin

Parmak izini onayladıktan sonra FAV sunucuyu denetler ve kurulumu başlatır. Uygulamayı kapatsanız da kurulum sunucuda devam eder. İlerlemeyi kurtarmak için FAV'ı yeniden açın; sudo parolayı tekrar isteyebilir.

## 5. İlk peer'inizi ekleyin

Kurulum ilk istemci profilini oluşturur. Başka bir profil için sunucu ayrıntılarında Eş ekle'yi kullanın. Aynı cihazda .conf dosyasını kaydedin veya paylaşın ve WireGuard ile açın. Başka bir cihazda içe aktarmak için WireGuard'ı o cihazda açın, QR ile içe aktarmayı seçin ve FAV'ın gösterdiği kodu tarayın.

İçe aktarılan tüneli kontrol edin, kaydedin ve etkinleştirin. Tam etiketler WireGuard platformuna ve sürümüne göre değişir; eş ayrıntılarında platforma özel talimatlar bulunur.

Trafiğiniz artık profilin IPv4 ve IPv6 varsayılan rotalarını kullanarak kendi sunucunuzdan geçiyor.

## IPv6 ve profil güvenliği

FAV IPv6'yı otomatik seçer. Sağlayıcının devrettiği `/64` ve doğrulanmış dönüş yolu varsa yönlendirilmiş IPv6 kullanır. Aksi durumda kalıcı bir ULA kullanır: profil IPv6'yı yine yakalar, ancak sunucu doğrudan geri dönüşe izin vermek yerine reddeder. IPv6 atlama seçeneği yoktur.

Bu, sunucu yapılandırmasını ve FAV'ın ürettiği profili doğrular; içe aktaran cihazı doğrulamaz. Dışa aktarma, bildirilen içe aktarma veya handshake; istemci rotalarını, kill switch'i ya da VPN durduğunda korumayı kanıtlamaz. Android'de WireGuard'ın Always-on VPN ve VPN olmadan bağlantıları engelle ayarlarını yalnızca varsa etkinleştirin ve o cihazda doğrulayın. Diğer platformlarda istemci/OS korumasını ayrı yapılandırıp test edin. QR kodları ve .conf dosyaları özel anahtarlar içerir: yalnızca hedef cihazla paylaşın.
