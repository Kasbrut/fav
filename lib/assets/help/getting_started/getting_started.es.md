# Tu primer servidor

Una guía paso a paso — no se requiere experiencia previa.

## 1. Consigue una máquina virtual

Una máquina virtual (a menudo llamada VPS) es un pequeño ordenador que funciona en un centro de datos y está siempre encendido. Lo alquilas por meses a un proveedor en la nube como Linode, DigitalOcean, Hetzner o Vultr. El plan más económico (normalmente 1 núcleo de CPU compartido y 1 GB de RAM) es más que suficiente para ejecutar una [VPN](glossary://vpn) personal.

Cuando pidas el servidor, elige la última versión estable de Debian o Ubuntu como sistema operativo. Anota tres cosas antes de cerrar el panel de control del proveedor: la dirección IP pública del servidor, el nombre de usuario de acceso (normalmente `root`) y la contraseña que te proporciona el proveedor.

## 2. Abre el puerto de WireGuard

Un [firewall](glossary://firewall) es un filtro que decide qué conexiones de red se permiten entrar y salir de tu servidor. La mayoría de los proveedores en la nube aplican un firewall de forma predeterminada, y bloquea todos los puertos que no hayas abierto explícitamente. WireGuard se comunica a través de un [puerto UDP](glossary://udp-port) — el predeterminado es 51820 — así que necesitas añadir una regla de entrada que permita el tráfico UDP en ese puerto.

Para obtener instrucciones paso a paso específicas de cada proveedor importante, consulta la entrada "Firewall y apertura de puertos" en esta sección de Ayuda. El panel de control de cada proveedor tiene un aspecto algo distinto, pero los pasos son los mismos: encuentra las reglas del firewall, añade una regla de entrada UDP para el puerto 51820 y guarda.

## 3. Añade el servidor a esta aplicación

Abre Servidores y elige Añadir un servidor. Introduce la dirección IP pública, el puerto SSH (22 de forma predeterminada), el nombre de usuario y la contraseña del paso 1. Revisa Opciones avanzadas solo si necesitas cambiar el puerto de WireGuard, la subred, DNS, el refuerzo, la monitorización o la copia de seguridad; después elige Conectar e instalar.

La aplicación se conecta a tu servidor por [SSH](glossary://ssh) — un canal cifrado — y te muestra de inmediato la [huella digital](glossary://fingerprint) del servidor. La huella digital es un código corto que identifica de forma única al servidor. Léela y confírmala solo si coincide con lo que ves en el panel de control de tu proveedor o en la salida de la consola. Una vez confirmada, la aplicación la recuerda y te avisará si alguna vez cambia — un cambio que no esperabas puede ser una señal de un problema de seguridad.

## 4. Espera a la instalación

Después de confirmar la huella digital, FAV comprueba el servidor e inicia la instalación. Esta continúa en el servidor si cierras la aplicación. Vuelve a abrir FAV para recuperar el progreso; sudo puede solicitar la contraseña de nuevo.

## 5. Añade tu primer peer

La instalación crea un primer perfil de cliente. Para crear otro, usa Añadir peer en los detalles del servidor. En el mismo dispositivo, guarda o comparte el archivo .conf y ábrelo con WireGuard. Para importarlo en otro dispositivo, abre WireGuard allí, elige la opción de importar mediante QR y escanea el código que muestra FAV.

Revisa el túnel importado, guárdalo y actívalo. Las etiquetas exactas varían según la plataforma y la versión de WireGuard; los detalles del peer incluyen instrucciones específicas para cada plataforma.

Tu tráfico ahora usa las rutas predeterminadas IPv4 e IPv6 del perfil a través de tu propio servidor.

## IPv6 y seguridad de los perfiles

FAV elige IPv6 automáticamente. Con un `/64` delegado por el proveedor y una ruta de retorno verificada usa IPv6 enrutado. De lo contrario usa una ULA persistente: el perfil sigue capturando IPv6, pero el servidor lo rechaza en vez de permitir un respaldo directo. No hay opción de omitir IPv6.

Esto verifica la configuración del servidor y el perfil generado por FAV, no el dispositivo que lo importa. Exportar, declarar una importación o ver un handshake no demuestra rutas del cliente, interruptor de seguridad ni protección cuando la VPN se detiene. En Android activa VPN siempre activa y Bloquear conexiones sin VPN de WireGuard solo si están disponibles y valídalas en ese dispositivo. En otras plataformas configura y prueba por separado la protección del cliente/SO. Los códigos QR y archivos .conf contienen claves privadas: compártelos solo con el dispositivo previsto.
