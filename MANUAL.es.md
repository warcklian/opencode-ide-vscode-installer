# OpenCode CLI - Manual de usuario

Guía práctica y completa para **usar OpenCode** una vez que este instalador
portable lo ha puesto en tu máquina. Todo lo que hay aquí es para **OpenCode V2**.
Todas las teclas son las **por defecto**; cada atajo se puede cambiar en
`~/.config/opencode/cli.json` (ver [Personalizar los atajos](#personalizar-los-atajos)).

> ¿Eres nuevo? Empieza por [Instalación y primera ejecución](#instalación-y-primera-ejecución),
> después lee [La tecla líder](#la-tecla-líder-ctrl--x) y
> [Modelos](#modelos-mostrar-y-seleccionar): esas dos secciones resuelven el 90 %
> de los «¿cómo hago para...?».

---

## Índice

1. [Instalación y primera ejecución](#instalación-y-primera-ejecución)
2. [Abrir OpenCode en Cursor / una terminal](#abrir-opencode-en-cursor--una-terminal)
3. [La interfaz (TUI) de un vistazo](#la-interfaz-tui-de-un-vistazo)
4. [La tecla líder (Ctrl + X)](#la-tecla-líder-ctrl--x)
5. [Modelos (mostrar y seleccionar)](#modelos-mostrar-y-seleccionar)
6. [Agentes / modos (Build, Plan, ...)](#agentes--modos-build-plan-)
7. [Sesiones y pestañas](#sesiones-y-pestañas)
8. [Comandos con barra](#comandos-con-barra)
9. [Prompts: archivos, rangos, imágenes, shell](#prompts-archivos-rangos-imágenes-shell)
10. [Deshacer, rehacer y compactar](#deshacer-rehacer-y-compactar)
11. [El visor de diferencias](#el-visor-de-diferencias)
12. [Apariencia y navegación](#apariencia-y-navegación)
13. [Editar el prompt (teclas de entrada)](#editar-el-prompt-teclas-de-entrada)
14. [Comandos de la CLI (no interactivos)](#comandos-de-la-cli-no-interactivos)
15. [Archivos de configuración](#archivos-de-configuración)
16. [Permisos](#permisos)
17. [Personalizar los atajos](#personalizar-los-atajos)
18. [Solución de problemas](#solución-de-problemas)
19. [Tarjeta de referencia rápida](#tarjeta-de-referencia-rápida)

---

## Instalación y primera ejecución

El instalador deja el binario `opencode` en `~/.opencode/bin` y (con tu
consentimiento) lo agrega al `PATH`. Consulta `README.md` para los detalles de
instalación.

Primera ejecución:

```bash
cd ~/code/mi-proyecto
opencode
```

La primera vez, OpenCode te pide **conectar un proveedor de modelo** (OpenCode
Zen, Anthropic, OpenAI, Google, un servidor local Ollama/LM Studio, ...). Elige
uno y completa el inicio de sesión. También puedes gestionar las credenciales
desde la CLI:

```bash
opencode auth list                 # lista los proveedores guardados
opencode auth login anthropic      # inicia sesión en un proveedor
opencode auth switch anthropic work
```

> Sin un proveedor de modelo conectado, OpenCode no puede responder. Esa es la
> causa más común de «no hace nada».

---

## Abrir OpenCode en Cursor / una terminal

OpenCode es una **aplicación de terminal**, no una extensión de Cursor. Edita los
archivos en disco, así que cualquier editor abierto en la misma carpeta (por
ejemplo Cursor) muestra los cambios en vivo.

1. En Cursor abre la terminal integrada: `` Ctrl+` ``.
2. Ve a tu proyecto: `cd ruta\al\proyecto`.
3. Ejecuta `opencode` (para trabajar en otra carpeta: `opencode ~/otro/proyecto`).

**Después de instalar o cambiar el `PATH`, reinicia Cursor por completo** (todas
las ventanas) para que las terminales nuevas hereden el entorno actualizado. A
veces no basta con abrir otra pestaña de terminal.

---

## La interfaz (TUI) de un vistazo

```
+---------------------------------------------------------------+
|  transcripción de la sesión (mensajes, herramientas, diffs)   |
|                                                               |
|  +---------------------------------------------------------+  |
|  | prompt input       > build - tu-modelo             # modelo
|  +---------------------------------------------------------+  |
+---------------------------------------------------------------+
```

- Escribe una petición y pulsa **Enter** para enviarla.
- El pie muestra el **agente activo** (`build`, `plan`, ...) y el **modelo
  activo**.
- Mientras OpenCode trabaja, **Enter** guía la sesión en curso; **Esc** la
  interrumpe.

Abre la **paleta de comandos** para ver todo lo disponible en la vista actual:

```
Ctrl + P
```

¿Olvidaste un atajo? Activa **which-key** para descubrir los atajos de forma
interactiva:

```
Ctrl + Alt + K
```

---

## La tecla líder (Ctrl + X)

La mayoría de las acciones de «control» usan una **tecla líder**: pulsa y suelta
**`Ctrl+X`**, y después pulsa la segunda tecla. Esto se escribe como
**`Ctrl+X` y luego `M`**.

| Pulsa `Ctrl+X` y luego... | Acción                                        |
| ------------------------- | --------------------------------------------- |
| **M**                     | **Listar / seleccionar modelos**              |
| **A**                     | **Listar / seleccionar agentes (modos)**      |
| **N**                     | Nueva sesión                                  |
| **L**                     | Listar sesiones                               |
| **W**                     | Cerrar la pestaña de sesión actual            |
| **B**                     | Mostrar/ocultar la barra lateral              |
| **T**                     | Mostrar/ocultar el panel de terminal          |
| **E**                     | Abrir el editor externo para el prompt        |
| **C**                     | Compactar la sesión (liberar contexto)        |
| **G**                     | Ver la línea de tiempo de la sesión           |
| **S**                     | Ver el estado                                 |
| **U**                     | Deshacer el último mensaje y su trabajo       |
| **R**                     | Rehacer el trabajo deshecho                   |
| **X**                     | Exportar la sesión a tu editor                |
| **Y**                     | Copiar el mensaje seleccionado                |
| **I**                     | Ver imágenes adjuntas                         |
| **Q**                     | Salir de OpenCode                             |
| **Enter**                 | Poner el prompt en cola para después          |

La tecla líder por defecto es `Ctrl+X` y se puede cambiar (por ejemplo a
`Ctrl+Space`) en `cli.json`.

---

## Modelos (mostrar y seleccionar)

### Por qué importa

OpenCode habla con un **proveedor/modelo**. Si el modelo falta, está deprecado o
el proveedor no está conectado, recibes un error en vez de una respuesta. **Un
modelo ya elegido para una sesión tiene prioridad sobre el valor por defecto de
la configuración**, así que la solución para una sesión rota suele ser cambiar el
modelo *de la sesión*, no el de la configuración.

### Cambiar el modelo de la sesión actual

- **`Ctrl+X` y luego `M`**: abre la lista de modelos, o
- escribe **`/models`** y pulsa Enter,
- elige una entrada (por ejemplo `opencode/big-pickle`,
  `anthropic/claude-sonnet-4-5`).

Dentro del diálogo de modelos:

| Tecla    | Acción                              |
| -------- | ----------------------------------- |
| `Ctrl+A` | Abrir la lista de proveedores       |
| `Ctrl+F` | Marcar/desmarcar un modelo favorito |
| Enter    | Seleccionar el modelo resaltado     |

Cambia rápidamente entre modelos usados recientemente:

| Tecla      | Acción                    |
| ---------- | ------------------------- |
| `F2`       | Siguiente modelo reciente |
| `Shift+F2` | Modelo reciente anterior  |

### Variantes de modelo

Algunos modelos exponen **variantes** (esfuerzo de razonamiento / presupuesto de
tokens), que se eligen con `#variante`, por ejemplo `openai/gpt-5.2#high`.

- `Ctrl+T`: cicla las variantes del modelo actual.

### Fijar el modelo por defecto (para sesiones nuevas)

Edita `~/.config/opencode/opencode.json` (global) o `./opencode.json` (proyecto):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/big-pickle"
}
```

Precedencia: **modelo de la sesión > config del proyecto > config global**.
Cambiar la configuración no reescribe el modelo de una sesión existente.

### Referencia

- Lista todos los modelos disponibles desde la CLI: `opencode models`
- Sintaxis del selector de modelo: `proveedor/modelo` o
  `proveedor/modelo#variante`

---

## Agentes / modos (Build, Plan, ...)

En OpenCode un **agente** es lo que podrías llamar un «modo»: un asistente con
nombre propio, con su propio prompt de sistema, modelo, permisos y herramientas.

### Cambiar de modo

- **`Shift+Tab`**: cicla al siguiente agente (la forma más rápida de alternar
  Build/Plan).
- **`Ctrl+X` y luego `A`**: abre la lista de agentes, o escribe **`/agents`**.

### Agentes integrados

| Agente       | Modo       | Qué hace                                                                    |
| ------------ | ---------- | --------------------------------------------------------------------------- |
| **Build**    | `primary`  | Agente de código por defecto. Herramientas permitidas; hace ediciones.      |
| **Plan**     | `primary`  | Explora y planifica **sin editar** archivos normales del proyecto.          |
| **General**  | `subagent` | Investigación y trabajo en varios pasos con herramientas amplias; no puede lanzar más subagentes. |
| **Explore**  | `subagent` | Busca y lee código o web sin editar archivos.                               |

Flujo típico: usa **Plan** para diseñar y **Build** para implementar.

- Los agentes primarios se ejecutan como el agente principal de tu sesión.
- Los subagentes corren en sesiones hijas, lanzados por el agente primario (la
  herramienta `subagent`). Prompt de ejemplo: *«Usa el subagente explore para
  encontrar dónde se configura la autenticación.»*

### Fijar el agente por defecto

```json
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "plan"
}
```

Si el valor por defecto configurado no está disponible, OpenCode usa `build` y,
si no, el primer agente visible que pueda ser primario.

### Agentes personalizados

Crea un archivo Markdown con frontmatter:

```md
---
description: Revisa cambios buscando errores y regresiones
mode: subagent
model: anthropic/claude-sonnet-4-5#high
---
Revisa los cambios actuales. Lista los hallazgos por gravedad con archivo y línea.
```

Ubicaciones: `~/.config/opencode/agents/<nombre>.md` (global) o
`.opencode/agents/<nombre>.md` (proyecto). Una ruta anidada forma parte del ID
(`.opencode/agents/team/reviewer.md` -> `team/reviewer`).

---

## Sesiones y pestañas

Una **sesión** es una conversación con su propio historial, modelo y agente.

| Tecla / comando          | Acción                                         |
| ------------------------ | ---------------------------------------------- |
| `Ctrl+X` y luego `N`     | Nueva sesión                                   |
| `Ctrl+X` y luego `L`     | Listar sesiones                                |
| `/new`                   | Nueva sesión (forma de comando con barra)      |
| `/sessions`              | Lista de sesiones                              |
| `Ctrl+O`                 | Sesiones y proyectos recientes juntos          |
| `Ctrl+R`                 | Renombrar la sesión actual                     |
| `Ctrl+D`                 | Eliminar la sesión actual                      |
| `Ctrl+X` y luego `X`     | Exportar la sesión a tu editor                 |
| `Ctrl+X` y luego `G`     | Línea de tiempo de la sesión                   |
| `Ctrl+X` y luego `C`     | Compactar (resumir para ahorrar contexto)      |
| `Esc`                    | Interrumpir el turno en curso                  |
| `Ctrl+B`                 | Mandar a segundo plano herramientas bloqueantes|

### Pestañas

Las pestañas están activadas por defecto.

| Tecla                 | Acción                          |
| --------------------- | ------------------------------- |
| `Ctrl+Tab`            | Siguiente pestaña de sesión     |
| `Ctrl+Shift+Tab`      | Pestaña de sesión anterior      |
| `Ctrl+1` ... `Ctrl+9` | Ir a la pestaña N               |
| `Ctrl+X` y luego `W`  | Cerrar la pestaña actual        |
| `Ctrl+Shift+T`        | Reabrir la última pestaña cerrada|

---

## Comandos con barra

Escribe `/` al inicio del prompt para listar y filtrar comandos.

| Comando      | Propósito                                            |
| ------------ | ---------------------------------------------------- |
| `/models`    | Elegir el modelo                                     |
| `/agents`    | Elegir el agente (modo)                              |
| `/new`       | Iniciar una sesión nueva                             |
| `/sessions`  | Listar y cambiar de sesión                           |
| `/undo`      | Revertir el último mensaje y el trabajo posterior    |
| `/redo`      | Restaurar el trabajo revertido                       |
| `/editor`    | Editar el prompt actual en tu `$EDITOR`              |
| `/btw <p>`   | Hacer una pregunta aparte sin añadirla al historial  |
| `/compact`   | Compactar la sesión                                  |
| `/diff`      | Abrir el visor de diferencias                        |
| `/help`      | Mostrar la ayuda                                     |

También puedes definir tus propios comandos `/` (ver la configuración de
`commands` del proyecto).

---

## Prompts: archivos, rangos, imágenes, shell

### Adjuntar archivos

Escribe **`@`** para buscar y adjuntar un archivo:

```text
Revisa @src/auth.ts buscando problemas de manejo de errores
Explica @src/auth.ts#20-45
```

### Ejecutar un comando de shell

Escribe **`!`** al inicio de un prompt vacío para entrar en modo shell; la salida
queda en la sesión:

```text
!git status
```

### Preguntas aparte

```text
/btw ¿por qué falló el test del paso 2?
```

Usa el contexto de la sesión y el modelo actual, pero **no** se añade a la
conversación.

### Entrada multilínea

Pulsa **`Shift+Enter`**, **`Ctrl+Enter`**, **`Alt+Enter`** o **`Ctrl+J`** para
insertar una nueva línea dentro del prompt.

---

## Deshacer, rehacer y compactar

- **`Ctrl+X` y luego `U`** (o `/undo`): revierte el último mensaje del usuario y
  el trabajo que le siguió. El mensaje vuelve al compositor para que lo edites.
- **`Ctrl+X` y luego `R`** (o `/redo`): restaura el trabajo revertido.
- Enviar un prompt nuevo acepta la reversión y continúa desde ahí.
- **`Ctrl+X` y luego `C`**: compacta la sesión cuando el contexto crece mucho.

---

## El visor de diferencias

Revisa lo que cambió el agente. Pulsa **`d`** para elegir el alcance: **All**
(todo), **Committed** (confirmado), **Uncommitted** (sin confirmar) o **Last
turn** (último turno); selecciona **Base** para cambiar la rama de comparación.

| Tecla               | Acción                                        |
| ------------------- | --------------------------------------------- |
| `j` / `k`           | Bajar / subir                                 |
| `Ctrl+F` / `Ctrl+B` | Página abajo / arriba                         |
| `n` / `p`           | Siguiente / anterior archivo (también `Alt+Abajo/Arriba`) |
| `]` / `[`           | Siguiente / anterior fragmento (hunk)         |
| `s`                 | Alternar vista de parche de un solo archivo   |
| `v`                 | Alternar vista dividida / unificada           |
| `b`                 | Alternar el árbol de archivos                 |
| `d`                 | Cambiar el alcance de la revisión             |
| `m`                 | Marcar archivo como revisado (oculta su parche)|
| `Esc` / `q`         | Cerrar el visor de diferencias                |

Usa el ratón para hacer clic en archivos o expandir carpetas.

---

## Apariencia y navegación

| Tecla / comando      | Acción                                    |
| -------------------- | ----------------------------------------- |
| `Ctrl+P`             | Paleta de comandos (incluye **Ajustes**)  |
| `Ctrl+X` y luego `B` | Mostrar/ocultar barra lateral             |
| `Ctrl+X` y luego `T` | Mostrar/ocultar panel de terminal         |
| `Ctrl+X` y luego `S` | Ver el estado                             |
| `Ctrl+Alt+K`         | Activar which-key (descubrir atajos)      |
| `Ctrl+C` / `Ctrl+D`  | Salir de OpenCode (`Ctrl+X` y luego `Q` también) |

Los ajustes comunes están en **`Ctrl+P` -> Open settings**, o en `cli.json`:
tema, animaciones, velocidad de scroll, barra lateral, visibilidad del
razonamiento, notificaciones, captura del ratón y más.

---

## Editar el prompt (teclas de entrada)

| Tecla                                    | Acción                        |
| ---------------------------------------- | ----------------------------- |
| `Enter`                                  | Enviar                        |
| `Shift+Enter` / `Ctrl+J` / `Alt+Enter`   | Nueva línea                   |
| `Ctrl+A` / `Ctrl+E`                      | Inicio / fin de línea         |
| `Alt+F` / `Alt+B` (o `Ctrl+Izq/Der`)     | Palabra adelante / atrás      |
| `Ctrl+W`                                 | Borrar palabra hacia atrás    |
| `Ctrl+U` / `Ctrl+K`                      | Borrar hasta inicio / fin de línea |
| `Ctrl+Shift+D`                           | Borrar la línea entera        |
| `Ctrl+-` luego `Ctrl+.`                  | Deshacer / rehacer en la entrada |
| `Ctrl+V`                                 | Pegar                         |
| `Arriba` / `Abajo`                       | Historial del prompt          |

---

## Comandos de la CLI (no interactivos)

Todos los comandos aceptan `--help`.

| Comando                          | Propósito                                           |
| -------------------------------- | --------------------------------------------------- |
| `opencode`                       | Abrir la TUI a pantalla completa                    |
| `opencode <dir>`                 | Abrir la TUI en otro proyecto                       |
| `opencode run "..."`             | Enviar un prompt y mostrar la respuesta (scripts/CI)|
| `opencode mini`                  | Interfaz interactiva mínima                         |
| `opencode session list`          | Gestionar sesiones                                  |
| `opencode auth list`             | Gestionar proveedores/credenciales                  |
| `opencode models`                | Listar los modelos disponibles                      |
| `opencode mcp list`              | Gestionar servidores MCP                            |
| `opencode plugin list`           | Gestionar plugins                                   |
| `opencode stats`                 | Estadísticas de uso                                 |
| `opencode serve`                 | Iniciar el servidor de API / web                    |
| `opencode service status`        | Controlar el servidor en segundo plano (`start/stop/restart`)|
| `opencode reload`                | Recargar la configuración sin reiniciar             |
| `opencode debug paths`           | Mostrar rutas globales (útil para soporte)          |
| `opencode upgrade`               | Actualizar OpenCode (alias: `opencode update`)      |
| `opencode uninstall`             | Eliminar OpenCode                                   |

Banderas útiles de `run`:

```bash
opencode run --model anthropic/claude-sonnet-4-5 "Refactoriza parseToken"
opencode run --agent build "Arregla el test que falla"
opencode run --continue "Ahora maneja el caso caducado"
opencode run --format json "Lista los comentarios TODO"
opencode run --file src/server.ts --file src/client.ts "Revisa estos por errores"
```

---

## Archivos de configuración

| Archivo                                 | Alcance                                  |
| --------------------------------------- | ---------------------------------------- |
| `~/.config/opencode/opencode.json(c)`   | Ajustes globales de servidor/proyecto    |
| `./opencode.json(c)`                    | Ajustes del proyecto                     |
| `./.opencode/opencode.json(c)`          | Ajustes del proyecto (anula los anteriores) |
| `~/.config/opencode/cli.json`           | Ajustes y atajos de la terminal (TUI)    |
| `~/.config/opencode/agents/<nombre>.md` | Agentes personalizados globales          |
| `./.opencode/agents/<nombre>.md`        | Agentes personalizados del proyecto      |

Ejemplo de config global de servidor:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/big-pickle",
  "default_agent": "build"
}
```

Ubicaciones (para soporte):

```bash
opencode debug paths
```

---

## Permisos

Los agentes se pueden restringir con reglas ordenadas (`allow`, `ask`, `deny`);
gana la última regla que coincide, así que pon primero las reglas amplias y luego
las excepciones.

```jsonc
{
  "permissions": [
    { "action": "edit",  "resource": "*", "effect": "ask" },
    { "action": "shell", "resource": "git push *", "effect": "deny" }
  ]
}
```

| Acción      | Cubre                                   |
| ----------- | --------------------------------------- |
| `shell`     | Comandos de shell                       |
| `edit`      | Herramientas de editar / escribir / aplicar |
| `read`      | Leer archivos locales                   |
| `glob`/`grep`| Herramientas de búsqueda local         |
| `subagent`  | Agentes hijos                           |
| `webfetch`/`websearch` | Herramientas web             |
| `skill`     | Carga de habilidades (skills)           |

Pon `"session.permissions": "autoaccept"` en `cli.json` para aceptar
automáticamente cada petición (úsalo con cuidado).

---

## Personalizar los atajos

Los atajos viven en `cli.json`. La tecla líder por defecto es `ctrl+x`; `<leader>`
en otro atajo se refiere a ella.

```json
{
  "keybinds": {
    "leader": "ctrl+space",
    "command.palette.show": "ctrl+k",
    "model.list": "<leader>m",
    "agent.list": "<leader>a"
  },
  "leader": { "timeout": 2000 }
}
```

- Una tecla: `"theme.switch": "ctrl+y"`.
- Alternativas: `"app.exit": "ctrl+c,ctrl+d"`.
- Desactivar: `"help.show": false` o `"none"`.
- Los IDs de comando desconocidos se rechazan.
- `leader.timeout` define cuánto esperar tras la tecla líder.

Algunos IDs útiles: `model.list`, `agent.list`, `session.new`, `session.list`,
`session.compact`, `session.undo`, `session.redo`, `prompt.editor`,
`terminal.toggle`, `session.sidebar.toggle`.

---

## Solución de problemas

| Síntoma | Causa / solución |
| --- | --- |
| **`opencode` no se reconoce** | La terminal/Cursor se inició antes del cambio de `PATH`. **Cierra Cursor por completo y vuelve a abrirlo** (o ejecuta `$env:Path += ";$env:USERPROFILE\.opencode\bin"` para la sesión actual). |
| **`Model <nombre> has been deprecated`** | Cambia el modelo con **`Ctrl+X` y luego `M`** (o `/models`). Es una corrección **por sesión**; una sesión nueva usa el modelo por defecto de la configuración. |
| **El cambio de `model` en la config parece ignorarse** | Una sesión que ya tiene modelo lo conserva. Cámbialo en la sesión (`Ctrl+X` `M`) o inicia una sesión nueva (`Ctrl+X` `N`). |
| **OpenCode pide conectar un proveedor / no hace nada** | No hay proveedor conectado. Ejecuta `opencode auth login <proveedor>` y elige un modelo. |
| **La TUI se ve mal en la terminal** | Usa una terminal con soporte de color verdadero (truecolor). En Cursor la terminal integrada funciona; si no, prueba `opencode mini`. |
| **Quiero ver qué hace cada tecla** | Pulsa `Ctrl+Alt+K` (which-key) o `Ctrl+P` (paleta de comandos). |
| **El contexto se hace enorme** | `Ctrl+X` y luego `C` (compactar), o inicia una sesión nueva. |
| **¿Dónde está mi configuración?** | `opencode debug paths`. La config global está en `~/.config/opencode/`. |

---

## Tarjeta de referencia rápida

```
ENVIAR / INTERRUMPIR
  Enter .................. enviar
  Shift/Ctrl/Alt+Enter ... nueva línea (también Ctrl+J)
  Esc .................... interrumpir el turno en curso

LÍDER = Ctrl+X  (pulsa, suelta y luego la siguiente tecla)
  Ctrl+X M ............... modelos (mostrar / seleccionar)
  Ctrl+X A ............... agentes = modos (Build / Plan / ...)
  Ctrl+X N ............... nueva sesión
  Ctrl+X L ............... listar sesiones
  Ctrl+X B ............... barra lateral
  Ctrl+X T ............... panel de terminal
  Ctrl+X E ............... editor externo
  Ctrl+X C ............... compactar
  Ctrl+X U / R ........... deshacer / rehacer
  Ctrl+X W ............... cerrar pestaña
  Ctrl+X Q ............... salir

MODOS / MODELOS
  Shift+Tab .............. ciclar agente (Build <-> Plan)
  Ctrl+T ................. ciclar variante del modelo
  F2 / Shift+F2 .......... ciclar modelos recientes

SESIONES / PESTAÑAS
  Ctrl+O ................. sesiones y proyectos recientes
  Ctrl+Tab / Ctrl+Shift+Tab  siguiente / anterior pestaña
  Ctrl+1..9 .............. ir a la pestaña
  Ctrl+Shift+T ........... reabrir pestaña cerrada

GLOBAL
  Ctrl+P ................. paleta de comandos (ajustes, acciones)
  Ctrl+Alt+K ............. which-key (descubrir atajos)
  Ctrl+C / Ctrl+D ........ salir

PROMPT
  @ ...................... adjuntar un archivo (ej. @src/app.ts#20-45)
  ! ...................... ejecutar un comando de shell
  / ...................... comandos con barra
```

---

Para el instalador, actualizaciones, uso sin conexión y seguridad, consulta
[`README.md`](README.md). Documentación oficial: <https://opencode.ai/v2/docs/>.

English version: [`MANUAL.md`](MANUAL.md).
