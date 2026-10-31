import path from 'path'
import { app, BrowserWindow, ipcMain, screen } from 'electron'
import serve from 'electron-serve'
import { startSmtc, stopSmtc } from './smtc'
import { startHelper, stopHelper } from './mac/helper'
import { attachGlass, applyGlass, cleanShapes, glassAvailable } from './mac/vibrancy'
import { startMacNowPlaying, stopMacNowPlaying } from './mac/nowplaying'
import { registerIpc } from './ipc'
import { stopMediaIpc } from './ipc/media'
import { stopPrivacyIpc } from './ipc/privacy'
import { stopUsageIpc } from './ipc/usage'
import { startScreenshotWatch, stopScreenshotWatch } from './ipc/screenshots'
import { setupNotchWindows } from './display'
import { applyContentProtection } from './ipc/system'
import { startUpdater } from './updater'
import { registerSettingsWindow } from './settingsWindow'
import { checkAndApplyFullscreenState, isTucked, stopFullscreenWatch } from './fullscreen'

// The app is now called CatNotch, but the data folder keeps its old name so nobody loses their tasks, settings or Claude hook token.
app.setPath('userData', path.join(app.getPath('appData'), 'DeskNotch'))

const isProd = process.env.NODE_ENV === 'production'

const STRIP_HEIGHT = 500

if (isProd) {
  serve({ directory: 'app' })
}

// The notch, and the rail beside it while open: every rectangle that takes
// clicks, per window (keyed by webContents id), as its renderer reports them.
type Rect = { x: number; y: number; width: number; height: number }
const notchBounds = new Map<number, Rect[]>()

/** One notch strip across the top of a display. */
const createNotchWindow = (bounds: Rect) => {
  const window = new BrowserWindow({
    ...bounds,
    // The fullscreen watcher (fullscreen.ts) knows its own window by this title.
    title: 'CatNotch',
    transparent: true,
    hasShadow: false,
    frame: false,
    resizable: false,
    movable: false,
    fullscreenable: false,
    skipTaskbar: true,
    // Windows: a tool window never lists on the taskbar or in Alt+Tab, even
    // after it takes focus (plain skipTaskbar can be lost then). macOS: a
    // panel floats over other apps without activating CatNotch.
    type: process.platform === 'darwin' ? 'panel' : 'toolbar',
    alwaysOnTop: true,
    // macOS pushes a window down below the menu bar (and the cutout); this
    // stops that clamp so the strip can sit at the very top of the display.
    enableLargerThanScreen: process.platform === 'darwin',
    webPreferences: {
      preload: path.join(import.meta.dirname, 'preload.js'),
      // The notch is a panel that is never the active app: without this, timers and animation frames can be throttled as "background", and the first hovers open slowly.
      backgroundThrottling: false,
    },
  })

  window.setAlwaysOnTop(true, 'screen-saver')
  // visibleOnFullScreen: stay over a full screen Space too (macOS only).
  window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  // macOS: the strip is not an app window, so Mission Control should not list it.
  if (process.platform === 'darwin') window.setHiddenInMissionControl(true)

  // macOS clamps a frame below the menu bar until the window is high enough,
  // so put it at the top edge again now that it is, and whenever it is shown.
  window.setBounds(bounds)
  window.on('show', () => window.setBounds(bounds))
  // Glass starts a screen capture, and macOS then shifts the strip up by the
  // cutout's height (taller by as much), so the notch's top slides off screen.
  // Whenever the frame drifts, put it back on its display's top edge.
  const pin = () => {
    const display = screen.getDisplayMatching(window.getBounds())
    const want = { x: display.bounds.x, y: display.bounds.y, width: display.bounds.width, height: bounds.height }
    const now = window.getBounds()
    if (now.x !== want.x || now.y !== want.y || now.width !== want.width || now.height !== want.height) window.setBounds(want)
  }
  window.on('move', pin)
  window.on('resize', pin)

  attachGlass(window)

  window.setIgnoreMouseEvents(true, { forward: true })
  // A notch made later (a display plugged in) honours Hide in screenshots too.
  applyContentProtection()

  // The strip spans the whole screen width, so it must never take clicks for
  // anything but the notch itself. The renderer reports the notch's bounds and
  // the cursor is polled against them: setIgnoreMouseEvents(false) would hand
  // the entire strip clicks, swallowing anything the user aimed at underneath.
  const contentsId = window.webContents.id
  let interactive = false
  let lastCursor = ''

  const applyCursorHitTest = () => {
    if (window.isDestroyed() || !window.isVisible()) return

    const { x, y } = screen.getCursorScreenPoint()
    const windowBounds = window.getBounds()

    const inside = (notchBounds.get(contentsId) ?? []).some(
      (r) =>
        x >= windowBounds.x + r.x &&
        x <= windowBounds.x + r.x + r.width &&
        y >= windowBounds.y + r.y &&
        y <= windowBounds.y + r.y + r.height,
    )

    // Where the pointer is, relative to the strip, whenever it moves: the
    // notch decides whether a pointer that left it has really gone. DOM events
    // cannot tell it, since the window stops taking the mouse past the edge.
    const at = `${x - windowBounds.x},${y - windowBounds.y}`
    if (at !== lastCursor) {
      lastCursor = at
      window.webContents.send('notch:cursor', { x: x - windowBounds.x, y: y - windowBounds.y })
    }

    if (inside === interactive) return
    interactive = inside
    window.setIgnoreMouseEvents(!inside, { forward: true })
  }

  // 60ms is under the threshold where a click feels like it missed, and cheap
  // enough to leave running.
  const hitTestTimer = setInterval(applyCursorHitTest, 60)
  window.on('closed', () => {
    clearInterval(hitTestTimer)
    notchBounds.delete(contentsId)
  })

  if (isProd) {
    void window.loadURL('app://./home')
  } else {
    const port = process.argv[2]
    void window.loadURL(`http://localhost:${port}/home`)
  }

  return window
}

app.whenReady().then(() => {
  if (process.platform === 'win32') {
    app.setAppUserModelId('com.devezio.desknotch')
  } else if (process.platform === 'darwin') {
    // No Dock icon or app switcher entry; the packaged app also sets LSUIElement.
    app.dock?.hide()
  }

  ipcMain.on('notch:bounds', (event, bounds: Rect[] | Rect) => {
    notchBounds.set(event.sender.id, Array.isArray(bounds) ? bounds : [bounds])
  })

  // Glass on macOS: the renderer sends the shapes of its glass surfaces and the
  // native blur view is cut to them (spec 0013).
  ipcMain.handle('glass:native', () => glassAvailable)
  ipcMain.on('notch:glass', (event, shapes: unknown) => {
    const window = BrowserWindow.fromWebContents(event.sender)
    if (window) applyGlass(window, cleanShapes(shapes))
  })

  // Only take keyboard focus when the notch is pinned open, so merely hovering
  // it does not steal focus from whatever the user was typing in.
  ipcMain.on('notch:pinned', (event, isPinned: boolean) => {
    const window = BrowserWindow.fromWebContents(event.sender)
    if (!window || window.isDestroyed()) return
    if (isPinned) window.focus()
    else window.blur()
    // Focus can put a window back on the taskbar; keep it off.
    window.setSkipTaskbar(true)
  })

  // A notch that just loaded asks whether it starts tucked behind a browser.
  ipcMain.handle('notch:tucked', (event) => isTucked(BrowserWindow.fromWebContents(event.sender)?.id ?? -1))

  ipcMain.on('notch:playback_session', (_event, session: any) => {
    for (const window of BrowserWindow.getAllWindows()) window.webContents.send('notch:playback_session', session)
  })

  // Handlers first, so a window created later (another display, or 'All')
  // finds them ready.
  registerIpc()
  registerSettingsWindow()
  startUpdater()
  startSmtc()
  if (process.platform === 'darwin') {
    startHelper()
    startMacNowPlaying()
  }
  startScreenshotWatch()
  setupNotchWindows(createNotchWindow, STRIP_HEIGHT)
  // Its PowerShell compiles C# on start; let the notch paint first.
  setTimeout(checkAndApplyFullscreenState, 2000)
})

// Quit from anywhere (Cmd+Q, the app's own Quit) stops the macOS children too.
app.on('before-quit', () => {
  stopHelper()
  stopMacNowPlaying()
})

app.on('window-all-closed', () => {
  stopSmtc()
  stopHelper()
  stopMacNowPlaying()
  stopMediaIpc()
  stopPrivacyIpc()
  stopUsageIpc()
  stopScreenshotWatch()
  stopFullscreenWatch()
  app.quit()
})
