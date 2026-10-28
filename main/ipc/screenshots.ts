/**
 * Screenshots, as they are taken. Windows 11's Snipping Tool (Win+Shift+S,
 * Print Screen) saves every capture to Pictures\Screenshots, so watching that
 * folder catches them as real files, ready to drag out or keep, for the cost
 * of a folder watch.
 *
 * ponytail: a capture copied to the clipboard only (auto-save switched off
 * in Snipping Tool) is missed; watching the clipboard would catch it.
 */
import { app, BrowserWindow, ipcMain, shell } from 'electron'
import fs from 'fs'
import path from 'path'
import { isScreenCapture, screenshotFolder } from '../mac/spotlight'

const IMAGE = /\.(png|jpe?g)$/i

let macFolder: string | null = null

const folders = () =>
  process.platform === 'darwin'
    ? macFolder && fs.existsSync(macFolder) ? [macFolder] : []
    : [path.join(app.getPath('pictures'), 'Screenshots'), process.env.OneDrive && path.join(process.env.OneDrive, 'Pictures', 'Screenshots')]
    .filter((dir): dir is string => Boolean(dir) && fs.existsSync(dir as string))
    .filter((dir, i, all) => all.indexOf(dir) === i)

const watchers: fs.FSWatcher[] = []
const seen = new Set<string>()

/** Waits until the file stops growing: the tool writes it in more than one go. */
const settled = async (file: string) => {
  let last = -1
  for (let i = 0; i < 20; i++) {
    const size = await fs.promises.stat(file).then((s) => s.size, () => -1)
    if (size > 0 && size === last) return true
    last = size
    await new Promise((resolve) => setTimeout(resolve, 150))
  }
  return false
}

/** An image directly inside a screenshot folder: the only files the capture
 *  card may touch, so these handlers can never be pointed anywhere else. */
const isCapture = (file: string) => IMAGE.test(file) && folders().some((dir) => path.dirname(file) === path.resolve(dir))

/** Discards a capture: to the Recycle Bin, so a slip can be undone. */
ipcMain.handle('screenshot:discard', async (_event, file: unknown) => {
  if (typeof file !== 'string') return false
  const resolved = path.resolve(file)
  if (!isCapture(resolved)) return false
  await shell.trashItem(resolved)
  return true
})

/** Renames a capture in its folder, keeping its extension. The new path, or
 *  null when the name is empty or already taken, or Windows refuses it. */
ipcMain.handle('screenshot:rename', async (_event, file: unknown, name: unknown) => {
  if (typeof file !== 'string' || typeof name !== 'string') return null
  const resolved = path.resolve(file)
  if (!isCapture(resolved)) return null
  // Characters Windows forbids in a name, and trailing dots or spaces it drops.
  const base = name.replace(/[<>:"/\\|?*\x00-\x1f]/g, '').trim().replace(/[. ]+$/, '')
  if (!base) return null
  const target = path.join(path.dirname(resolved), base + path.extname(resolved))
  if (target === resolved) return resolved
  // A change of case only is the same file to Windows, not a clash.
  if (target.toLowerCase() !== resolved.toLowerCase() && fs.existsSync(target)) return null
  // The watcher sees the new name as a new file; it is not a new capture.
  seen.add(target)
  try {
    await fs.promises.rename(resolved, target)
    return target
  } catch {
    return null
  }
})

export async function startScreenshotWatch() {
  if (process.platform === 'darwin') macFolder = await screenshotFolder()
  for (const dir of folders()) {
    try {
      watchers.push(
        fs.watch(dir, async (_event, name) => {
          if (!name || !IMAGE.test(name)) return
          const file = path.join(dir, name.toString())
          if (seen.has(file)) return
          seen.add(file)
          // Only new captures: a rename or touch of an old file is not one.
          const born = await fs.promises.stat(file).then((s) => s.birthtimeMs, () => 0)
          if (Date.now() - born > 10_000 || !(await settled(file))) return
          // macOS: only what Spotlight flags as a screenshot, not any picture saved to the folder.
          if (process.platform === 'darwin' && !(await isScreenCapture(file))) return
          for (const window of BrowserWindow.getAllWindows()) window.webContents.send('screenshot:new', file)
        }),
      )
    } catch (error) {
      console.warn('[screenshots] cannot watch', dir, (error as Error).message)
    }
  }
}

export function stopScreenshotWatch() {
  for (const watcher of watchers.splice(0)) watcher.close()
}
