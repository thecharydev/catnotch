/** Spotlight lookups for macOS: recent files and the screenshot folder. Every
 *  call is a child process, so main's event loop never waits on the index. */
import { execFile } from 'child_process'
import os from 'os'
import path from 'path'

const run = (cmd: string, args: string[]) =>
  new Promise<string>((resolve) =>
    execFile(cmd, args, { maxBuffer: 16 << 20 }, (_error, stdout) => resolve(stdout ?? '')),
  )

/** Files opened in the last 7 days, newest first. Library, hidden folders and
 *  app bundles are noise, so they are left out. */
export const recentPaths = async (limit: number): Promise<string[]> => {
  const found = (
    await run('mdfind', [
      '-onlyin',
      os.homedir(),
      "kMDItemLastUsedDate >= $time.today(-7) && kMDItemContentTypeTree != 'public.folder'",
    ])
  )
    .split('\n')
    .filter((file) => file && !file.includes('/Library/') && !/\/\./.test(file) && !file.endsWith('.app'))
    .slice(0, 300)
  if (!found.length) return []

  // `-raw` separates the values with NUL, one per file, in the order given.
  const dates = (await run('mdls', ['-name', 'kMDItemLastUsedDate', '-raw', ...found])).split('\0')
  return found
    .map((file, i) => ({ file, at: Date.parse(dates[i]?.replace(' +0000', 'Z').replace(' ', 'T')) || 0 }))
    .sort((a, b) => b.at - a.at)
    .slice(0, limit)
    .map((entry) => entry.file)
}

/** Where the system saves screenshots: the user's choice, else the Desktop. */
export const screenshotFolder = async (): Promise<string> => {
  const set = (await run('defaults', ['read', 'com.apple.screencapture', 'location'])).trim()
  if (!set) return path.join(os.homedir(), 'Desktop')
  return path.resolve(set.startsWith('~') ? path.join(os.homedir(), set.slice(1)) : set)
}

/** True when Spotlight marks the file as a screenshot, in any system language.
 *  The flag can land a moment after the file does, so ask a few times. */
export const isScreenCapture = async (file: string) => {
  for (let i = 0; i < 8; i++) {
    if ((await run('mdls', ['-name', 'kMDItemIsScreenCapture', '-raw', file])).trim() === '1') return true
    await new Promise((resolve) => setTimeout(resolve, 250))
  }
  return false
}
