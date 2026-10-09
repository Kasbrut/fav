# Preguntas frecuentes

## ¿Qué es una VPN, en una frase?

Una VPN es un túnel entre tu dispositivo y un servidor: el tráfico de tu dispositivo parece provenir del servidor, y la conexión entre tu dispositivo y el servidor está cifrada.

## ¿Por qué necesito mi propio servidor?

Controlas el servidor VPN y su configuración. Aun así, debes confiar en el proveedor de alojamiento y los administradores, que pueden observar metadatos de red. Una VPN propia no te hace anónimo.

## ¿Cuánto cuesta mantenerla?

FAV es gratuito. El coste del alojamiento y del tráfico depende del proveedor y del plan; consulta sus precios y límites actuales.

## ¿La contraseña que escribo en la aplicación se guarda en mi dispositivo?

Las contraseñas de acceso y sudo se solicitan cuando son necesarias y no se guardan como datos de la aplicación. La clave SSH se genera durante la instalación, incluso sin endurecimiento, y se conserva en el almacenamiento seguro.

## ¿Puedo trasladar mi servidor a otro dispositivo?

Sí. Abre Ajustes → Copia de seguridad y restauración para crear un archivo `.favbackup` cifrado con contraseña. Restáuralo solo en una instalación vacía de FAV y evita gestionar los mismos servidores desde ambos dispositivos. Si perdiste el dispositivo anterior o fue comprometido, FAV puede rotar sus claves SSH y, tras dos confirmaciones, revocar todos los peers existentes en los servidores accesibles.

## ¿Puede la aplicación enrutar mi dispositivo a través de la VPN automáticamente?

Todavía no. Hoy la aplicación configura el servidor — tu dispositivo se conecta mediante la aplicación oficial de WireGuard. Integrar el cliente en esta aplicación está en la hoja de ruta a largo plazo.

## ¿Qué hace "Activar refuerzo"?

El refuerzo (en Opciones avanzadas, desactivado de forma predeterminada) blinda todo el servidor tras la instalación: desactiva el inicio de sesión SSH con contraseña (solo inicio con clave), desactiva el acceso SSH como root y añade protección contra ataques de fuerza bruta. Se aplica al usuario con el que la app gestiona el servidor: el que crea para un inicio como root, o tu usuario existente para un inicio sin root con sudo. La app comprueba primero que tu inicio de sesión por clave funciona y revierte todo automáticamente si algo va mal, pero mantén siempre a mano la consola de tu proveedor como vía de regreso.

## ¿Cómo elimino un servidor?

En Servidores, desliza un servidor, usa su menú o elige Eliminar servidor en sus detalles. Selecciona **Eliminar VPN y servicios** para ejecutar una limpieza remota antes de que FAV lo olvide; cuando corresponda, también puedes deshacer el refuerzo SSH. Deja esa opción desactivada y elige **Desconectar FAV y eliminar** para quitar de forma remota solo la clave SSH de FAV y dejar la VPN funcionando. **Olvidar sin contactar con el servidor** elimina solo los datos locales y deja todos los cambios remotos, incluida la clave SSH de FAV; úsalo solo si el servidor no está disponible o lo limpiarás tú. Puedes reintentar los pasos remotos fallidos antes de optar por la eliminación solo local.

## Tengo problemas — ¿qué debo hacer?

Consulta la sección **Códigos de error** en esta pestaña de Ayuda si viste un error en rojo. Si aún no encuentras una solución, usa **Informar de un problema** para abrir una incidencia de GitHub ya rellenada.

## IPv6 y seguridad de los perfiles

Los nuevos perfiles v2 incluyen rutas predeterminadas IPv4 e IPv6; FAV no tiene un ajuste para omitir IPv6. Solo usa IPv6 enrutado tras verificar la ruta de retorno de un `/64` delegado por el proveedor. De lo contrario, el modo bloqueado captura IPv6 en un túnel ULA y lo rechaza en el servidor, en lugar de usar IPv6 directo. Un endpoint IPv6 público no es esa prueba.

FAV solo verifica el resultado del servidor y el perfil generado. La exportación, una importación declarada y un handshake de WireGuard no verifican las rutas ni un interruptor de seguridad del cliente, y no protegen el tráfico cuando se detiene la VPN. Configura y valida por separado la protección del cliente/SO. En Android revisa en el dispositivo destino VPN siempre activa y Bloquear conexiones sin VPN; FAV no ha verificado su disponibilidad ni comportamiento. Usa un servidor dedicado y conserva acceso a la consola. Los códigos QR y archivos .conf contienen claves privadas: compártelos solo con el dispositivo previsto.
