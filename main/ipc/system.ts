/** Readings about the machine itself. */
import { BrowserWindow, desktopCapturer, ipcMain, screen } from 'electron'
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

  /** The capture source for the display the notch is on, for the renderer to stream. */
  ipcMain.handle('glass:source', async (event) => {
    const window = BrowserWindow.fromWebContents(event.sender)
    if (!window) return null
    const display = screen.getDisplayMatching(window.getBounds())
    const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 } })
    return (sources.find((s) => s.display_id === String(display.id)) ?? sources[0])?.id ?? null
  })
}

