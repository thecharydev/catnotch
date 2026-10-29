/** Most used and installed apps on macOS. An app's id is its .app path. The
 *  list comes from the folders apps live in, the launch counts from Spotlight. */
import { ipcMain, nativeImage, shell } from 'electron'
import { execFile } from 'child_process'
import fs from 'fs'
import os from 'os'
import path from 'path'

interface TopApp {
  id: string
  name: string
  icon: string | null
}

const ROOTS = ['/Applications', '/System/Applications', path.join(os.homedir(), 'Applications')]
const FRESH = 30 * 60_000
const COUNT = 12

let installed: { at: number; apps: { id: string; name: string }[] } | null = null

/** Every .app in the usual folders (and one level down, for Utilities and
 *  vendor folders), by name. */
const allApps = async () => {
  if (installed && Date.now() - installed.at < FRESH) return installed.apps
  const found = new Map<string, string>()
  const scan = async (dir: string, depth: number) => {
    let entries: fs.Dirent[] = []
    try {
      entries = await fs.promises.readdir(dir, { withFileTypes: true })
    } catch {
      return
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name)
      if (entry.name.endsWith('.app')) found.set(full, entry.name.slice(0, -4))
      else if (entry.isDirectory() && depth > 0 && !entry.name.startsWith('.')) await scan(full, depth - 1)
    }
  }
  for (const root of ROOTS) await scan(root, 1)
  const apps = [...found].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name))
  installed = { at: Date.now(), apps }
  return apps
}

/** Launch counts, by app path. Zero for an app Spotlight has never seen opened
 *  (and for every app when Spotlight is off). */
const useCounts = (paths: string[]) =>
  new Promise<Map<string, number>>((resolve) => {
    if (!paths.length) return resolve(new Map())
    // `-raw` prints the values NUL separated, in the order given.
    execFile('mdls', ['-name', 'kMDItemUseCount', '-raw', '-nullMarker', '0', ...paths], { maxBuffer: 8 << 20 }, (_error, stdout) => {
      const values = (stdout ?? '').split('\0')
      resolve(new Map(paths.map((p, i) => [p, Number(values[i]) || 0])))
    })
  })

const icons = new Map<string, string | null>()

const withIcon = async (entry: { id: string; name: string }): Promise<TopApp> => {
  if (!icons.has(entry.id)) {
    // Not app.getFileIcon: on macOS it kills the whole process (SIGTRAP, a
    // native crash no catch can stop) as soon as a few app icons are asked for.
    icons.set(
      entry.id,
      await nativeImage.createThumbnailFromPath(entry.id, { width: 64, height: 64 }).then(
        (image) => (image.isEmpty() ? null : image.toDataURL()),
        () => null,
      ),
    )
  }
  return { ...entry, icon: icons.get(entry.id) ?? null }
}

let top: { at: number; apps: TopApp[] } | null = null

const topApps = async () => {
  if (top && Date.now() - top.at < FRESH) return top.apps
  const apps = await allApps()
  const counts = await useCounts(apps.map((a) => a.id))
  const ranked = apps
    .filter((a) => (counts.get(a.id) ?? 0) > 0 && a.id !== path.dirname(path.dirname(path.dirname(process.execPath))))
    .sort((a, b) => (counts.get(b.id) ?? 0) - (counts.get(a.id) ?? 0))
    .slice(0, COUNT)
  top = { at: Date.now(), apps: await Promise.all(ranked.map(withIcon)) }
  return top.apps
}

export function registerMacAppsIpc() {
  ipcMain.handle('apps:top', () => topApps())
  ipcMain.handle('apps:all', () => allApps())
  // Only apps this side has listed: nothing arbitrary from the page.
  ipcMain.handle('apps:describe', async (_event, ids: unknown) => {
    const listed = new Map((await allApps()).map((a) => [a.id, a]))
    const wanted = (Array.isArray(ids) ? ids : []).filter((id): id is string => typeof id === 'string').slice(0, 24)
    return Promise.all(wanted.flatMap((id) => (listed.has(id) ? [withIcon(listed.get(id)!)] : [])))
  })
  ipcMain.handle('apps:launch', async (_event, id: unknown) => {
    if (typeof id !== 'string') return
    if ((await allApps()).some((a) => a.id === id)) void shell.openPath(id)
  })
}
