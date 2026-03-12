# Minecraft Bedrock Server Dashboard MVP

Consola de administración gráfica y sistema de backups automáticos para servidores de **Minecraft Bedrock Edition** en Windows.

## Características Principales

1. **Dashboard UI Interactivo**: Panel limpio, fácil de usar e intuitivo con acceso rápido a comandos de administrador.
2. **Backups Automáticos Transparentes**: Realiza respaldos del mundo de manera segura en el fondo sin tener que desconectar (kickear) a los jugadores en medio de la partida. Mantiene solo los respaldos más recientes.
3. **Instalador de Actualizaciones de 1 Clic**: El sistema comprueba automáticamente contra los servidores de Mojang si hay una versión nueva del juego. De haberla, te permite descargarla, extraerla e instalarla sin perder tu configuración local con la pulsación de un solo botón.
4. **Integración con Playit.gg**: Soporte listo para servidores expuestos a través de túneles playit.gg.

## Requisitos

- **Windows 10 / 11**
- **Python 3.8 o superior**

## Instalación

1. Clona este repositorio o descarga el código fuente y ponlo en tu servidor local.
2. Descarga los binarios base del servidor original de _Minecraft Bedrock_ directamente desde el dashboard o colócalos tú mismo al lado de estos `.py` y `.ps1`.
3. Ejecuta el archivo python para inicializar:
   ```bash
   python server_dashboard.py
   ```
4. En el primer lanzamiento, se autogenerará un archivo `config.json` en el cual podrás especificar cosas como tu nombre de la carpeta del mundo, la ruta de tu Playit y el intervalo de los respaldos.

## Uso del Auto-Backup sin el panel

Si lo deseas, puedes ejecutar de forma individual `backup_auto.ps1` usando el Programador de Tareas de Windows para respaldar el servidor de manera rutinaria aunque el panel de Python esté cerrado. El script buscará automáticamente tu nombre de mundo leyendo el `server.properties`.

## Guía de Conexión y Apertura de Puertos con Playit.gg

Si no puedes abrir puertos en tu router o quieres más seguridad, puedes usar Playit.gg. El dashboard está preparado para iniciarlo junto al servidor de forma invisible.

**Si es tu primera vez usando Playit:**

1. Regístrate en [Playit.gg](https://playit.gg/) creando una cuenta gratuita e inicia sesión.
2. Descarga el programa para Windows desde su página web e instálalo.
3. Al instalar y ejecutar el programa en tu PC por primera vez, te dará un enlace que abrirá tu navegador web para "vincular" tu Computadora (Agente) con tu cuenta. Aprobar la vinculación.
4. En la web de Playit, ve a **Tunnels** y haz clic en **"Add Tunnel"**.
5. Importante: Selecciona como tipo de juego **"Minecraft Bedrock"** (asegurándote de que dice **UDP**) y que apunte al puerto local **19132** (el puerto por defecto de Bedrock).
6. ¡Creado! En la web te aparecerá una dirección pública generada (ej: `oso-tubo.playit.gg` y puerto `45612`). Esa es la IP que le darás a tus jugadores para entrar.

**Integración con tu Panel (Dashboard):**

1. Asegúrate de conocer la ruta donde se instaló tu programa Playit (usualmente está en `C:\\Program Files\\playit_gg\\bin\\playit.exe`).
2. La primera vez que abras el _Dashboard_ se generará un archivo `config.json` en la misma carpeta. Ábrelo con el block de notas.
3. Edita la línea de `"playit_exe_path"` y pon ahí la ruta de tu ejecutable. Si la copiaste de Windows, asegúrate de reemplazar cada antibarra `\` por una doble antibarra `\\` (ej: `"C:\\Program Files\\playit_gg\\bin\\playit.exe"`).
4. Guarda el archivo `config.json`.

¡Magia! La próxima vez que pulses el botón "INICIAR SERVIDOR", el panel de control se encargará de levantar automáticamente y en modo invisible la conexión de Playit, abriendo tu servidor al mundo de un solo clic.

## Estructura

```
server_dashboard.py   -> La UI gráfica en Tkinter.
backup_auto.ps1       -> Script PowerShell asíncrono que copia los datos y avisa ingame.
config.json           -> (Auto-generado) Ajustes personalizados para el usuario.
```

¡Disfruta organizando tu servidor sin el clásico dolor de cabeza!

## Créditos y Agradecimientos

- **API de Descargas de Bedrock**: Un agradecimiento especial a **[kittizz](https://github.com/kittizz/bedrock-server-downloads)** por proveer la API comunitaria que este dashboard utiliza para buscar y detectar las versiones más recientes del servidor de Minecraft Bedrock de forma rápida y segura.
