/** Readings about the machine itself. */
import { BrowserWindow, desktopCapturer, dialog, ipcMain, screen, shell, systemPreferences } from 'electron'
import os from 'os'
import { readStore } from '../store'

/** Notch windows whose Glass backdrop is live. */
const glassOn = new Set<number>()

/**
 * Leaves the notch out of screenshots and screen sharing (WDA_EXCLUDEFROMCAPTURE):
 * always under Glass, which needs to capture what is behind it, and whenever
 * the Hide in screenshots setting is on. Called when either changes and when
 * a notch window is made.
 */
export const applyContentProtection = () => {
  const hide = readStore().settings?.hideInScreenshots === true
  for (const window of BrowserWindow.getAllWindows()) window.setContentProtection(hide || glassOn.has(window.id))
}

export function registerSystemIpc() {
  /** Memory pressure and uptime, read from Node rather than a native module. */
  ipcMain.handle('system:stats', () => {
    const total = os.totalmem()
    const free = os.freemem()

    return {
      memoryUsed: (total - free) / total,
      uptimeSeconds: os.uptime(),
    }
  })

  /**
   * Glass: the notch shows a live, blurred view of what is behind it. For
   * that, Windows is asked to leave this window out of screen capture
   * (`setContentProtection`, WDA_EXCLUDEFROMCAPTURE), so capturing the screen
   * returns what is underneath the notch rather than the notch itself. The
   * cost, said plainly in Settings: while Glass is on, the notch does not
   * appear in screenshots or screen shares.
   */
  ipcMain.handle('glass:protect', (event, on: unknown) => {
    const window = BrowserWindow.fromWebContents(event.sender)
    if (!window) return
    if (on === true) glassOn.add(window.id)
    else glassOn.delete(window.id)
    applyContentProtection()
  })

  /**
   * macOS: Glass captures the screen, which needs Screen Recording. Turning
   * Glass on explains that first, then asks; the answer is whether it may
   * run. Elsewhere there is nothing to ask. A denied permission can only be
   * changed in System Settings, so the dialog offers to open it.
   */
  ipcMain.handle('glass:permission', async (): Promise<boolean> => {
    if (process.platform !== 'darwin') return true
    if (systemPreferences.getMediaAccessStatus('screen') === 'granted') return true
    const denied = systemPreferences.getMediaAccessStatus('screen') === 'denied'
    const { response } = await dialog.showMessageBox({
      type: 'info',
      title: 'CatNotch',
      message: 'Glass needs Screen Recording',
      detail:
        'Glass shows a live, blurred view of what is behind the notch, so macOS asks you to allow Screen Recording. ' +
        'CatNotch only looks at the strip behind the notch, and nothing leaves your Mac.' +
        (denied ? '\n\nIt was turned off before: switch CatNotch on in System Settings, Privacy and Security, Screen Recording.' : ''),
      buttons: [denied ? 'Open System Settings' : 'Continue', 'Not now'],
      defaultId: 0,
      cancelId: 1,
      noLink: true,
    })
    if (response !== 0) return false
    if (denied) void shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture')
    // Asking for a capture source is what makes macOS show its prompt.
    else await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 } }).catch(() => [])
    return systemPreferences.getMediaAccessStatus('screen') === 'granted'
  })

  /** The capture source for the display the notch is on, for the renderer to stream. */
  ipcMain.handle('glass:source', async (event) => {
    const window = BrowserWindow.fromWebContents(event.sender)
    if (!window) return null
    const display = screen.getDisplayMatching(window.getBounds())
    const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 } })
    return (sources.find((s) => s.display_id === String(display.id)) ?? sources[0])?.id ?? null
  })
}

