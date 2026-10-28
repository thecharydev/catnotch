/**
 * The status the closed notch shows at its edge: privacy dots (which apps are
 * using the microphone or camera right now), Wi-Fi, and Bluetooth.
 *
 * - Microphone and camera: Windows keeps this itself, for its own tray icon.
 *   Under ConsentStore, every app that asked for a device has
 *   LastUsedTimeStart/Stop, and a Stop of 0 means "still using it". The key's
 *   name is the app: a package family for Store apps, the exe's path (with #
 *   for \\) under NonPackaged for the rest.
 * - Wi-Fi: `netsh wlan show interfaces`, the network name and signal.
 * - Bluetooth: the paired devices whose "is connected" property is true, and
 *   the battery level of those that report one (headsets, mice, pens).
 *
 * One PowerShell stays alive and prints a line only when something changes,
 * so an idle check costs nothing on this side.
 *
 * ponytail: polled (privacy 1.5 s, Wi-Fi ~10 s, Bluetooth ~30 s, since asking
 * every Bluetooth device takes a second or two) rather than watched; native
 * watchers would need a native module, add one if the lag matters.
 */
import { BrowserWindow, ipcMain } from 'electron'
import { type ChildProcess, spawn } from 'child_process'
import { nameOf, warmNames } from './apps'

export interface BluetoothDevice {
  name: string
  /** Percent, for devices that report it; null for the rest. */
  battery: number | null
}

export interface PrivacyState {
  mic: boolean
  camera: boolean
  /** The apps using each device, by the name they show under. */
  micApps: string[]
  cameraApps: string[]
  /** The Wi-Fi network, when connected. */
  wifi: { name: string; signal: number } | null
  /** Connected Bluetooth devices. */
  bluetooth: BluetoothDevice[]
}

let state: PrivacyState = { mic: false, camera: false, micApps: [], cameraApps: [], wifi: null, bluetooth: [] }
let watcher: ChildProcess | null = null

/** Device properties, as PnP names them: connected, and battery percent. */
const BT_CONNECTED = '{83DA6326-97A6-4088-9453-A1923F573B29} 15'
const BT_BATTERY = '{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2'

const SCRIPT = (parent: number) => `
$base = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore'
function Live($device) {
  (Get-ChildItem "$base\\$device" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.GetValue('LastUsedTimeStop') -eq 0 -and $_.GetValue('LastUsedTimeStart') -gt 0 } |
    ForEach-Object { $_.PSChildName } | Select-Object -Unique) -join ';'
}
function Wifi {
  $lines = netsh wlan show interfaces 2>$null
  $s = ($lines | Select-String '^\\s+State\\s+:\\s+(.+)$' | Select-Object -First 1).Matches.Groups[1].Value
  if ($s -ne 'connected') { return '' }
  $ssid = ($lines | Select-String '^\\s+SSID\\s+:\\s+(.+)$' | Select-Object -First 1).Matches.Groups[1].Value
  $sig = ($lines | Select-String '^\\s+Signal\\s+:\\s+(\\d+)%' | Select-Object -First 1).Matches.Groups[1].Value
  "$ssid|$sig"
}
function Bluetooth {
  $devs = Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -notmatch 'Enumerator|Radio|Adapter|Transport|Service|Protocol|RFCOMM|Generic|Avrcp|Wireless Bluetooth' }
  if (-not $devs) { return '' }
  $ids = $devs | Get-PnpDeviceProperty -KeyName '${BT_CONNECTED}' -ErrorAction SilentlyContinue |
    Where-Object { $_.Data -eq $true } | ForEach-Object { $_.InstanceId }
  if (-not $ids) { return '' }
  $on = $devs | Where-Object { $ids -contains $_.InstanceId }
  # The battery is only asked of connected devices, and only some answer.
  $levels = @{}
  $on | Get-PnpDeviceProperty -KeyName '${BT_BATTERY}' -ErrorAction SilentlyContinue |
    Where-Object { $null -ne $_.Data } | ForEach-Object { $levels[$_.InstanceId] = $_.Data }
  ($on | ForEach-Object { "$($_.FriendlyName)|$($levels[$_.InstanceId])" } | Select-Object -Unique) -join ';'
}
$last = ''; $tick = 0; $wifi = ''; $bt = ''
while ($true) {
  if (-not (Get-Process -Id ${parent} -ErrorAction SilentlyContinue)) { exit }
  if ($tick % 7 -eq 0) { $wifi = Wifi }
  if ($tick % 20 -eq 0) { $bt = Bluetooth }
  $now = "$(Live 'microphone')\`t$(Live 'webcam')\`t$wifi\`t$bt"
  if ($now -ne $last) { [Console]::Out.WriteLine($now); [Console]::Out.Flush(); $last = $now }
  $tick++
  Start-Sleep -Milliseconds 1500
}`

/**
 * A ConsentStore key's name, read off the key itself, for apps the Start menu
 * does not list: "C:#Program Files#Zoom#bin#Zoom.exe" → "Zoom",
 * "Microsoft.WindowsCamera_8wekyb3d8bbwe" → "Windows Camera".
 */
const appName = (key: string) => {
  const leaf = key.split('#').pop() ?? key
  // Exe names are often all lower case ("brave.exe"); a name starts with a capital.
  if (/\.exe$/i.test(leaf)) return leaf.replace(/\.exe$/i, '').replace(/^./, (c) => c.toUpperCase())
  const family = leaf.split('_')[0]
  return (family.split('.').pop() ?? family).replace(/([a-z])([A-Z])/g, '$1 $2')
}

/** The keys as the Start menu names them ("WhatsApp"), else as read above. */
const named = async (keys: string[]) => [...new Set(await Promise.all(keys.map(async (key) => (await nameOf(key)) ?? appName(key))))]

const keys = (field: string) => field.split(';').filter(Boolean)

/** "C:#…#Zoom.exe<TAB><TAB>Home|90<TAB>Buds|80;Mouse|" → the state, with the
 *  app keys still raw: `named` turns them into names. */
const parse = (line: string): PrivacyState | null => {
  const parts = line.split('\t')
  if (parts.length !== 4) return null
  const [mic, camera, wifi, bt] = parts
  const [name, signal] = wifi.split('|')
  const micApps = keys(mic)
  const cameraApps = keys(camera)
  return {
    mic: micApps.length > 0,
    camera: cameraApps.length > 0,
    micApps,
    cameraApps,
    wifi: wifi ? { name, signal: Number(signal) || 0 } : null,
    bluetooth: bt
      ? bt
          .split(';')
          .filter(Boolean)
          .map((entry) => {
            // The level follows the last |, so a | in a device's name is harmless.
            const at = entry.lastIndexOf('|')
            const level = Number(entry.slice(at + 1))
            return { name: entry.slice(0, at), battery: entry.slice(at + 1) && Number.isFinite(level) ? level : null }
          })
      : [],
  }
}

const start = () => {
  if (watcher) return
  // The app names are looked up in the Start menu's list; have it ready.
  warmNames()
  watcher = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', SCRIPT(process.pid)], {
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'ignore'],
  })
  // No PowerShell (macOS): no dots instead of crashing main.
  watcher.on('error', () => {})
  let buffer = ''
  let latest = 0
  watcher.stdout?.on('data', (chunk: Buffer) => {
    buffer += chunk.toString()
    const lines = buffer.split(/\r?\n/)
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      // Not trimmed: a reading with nothing in it is three tabs and no more.
      const next = parse(line)
      if (!next) continue
      // Naming is async; should a newer reading land first, the older is dropped.
      const mine = ++latest
      void Promise.all([named(next.micApps), named(next.cameraApps)]).then(([micApps, cameraApps]) => {
        if (mine !== latest) return
        state = { ...next, micApps, cameraApps }
        for (const window of BrowserWindow.getAllWindows()) window.webContents.send('privacy:state', state)
      })
    }
  })
  watcher.on('exit', () => {
    watcher = null
  })
}

export function registerPrivacyIpc() {
  // The first ask starts the watcher; the answer after that comes as events.
  ipcMain.handle('privacy:get', () => {
    start()
    return state
  })
}

export function stopPrivacyIpc() {
  watcher?.kill()
  watcher = null
}
