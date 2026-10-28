import { BrowserWindow, screen } from 'electron'
import { spawn, ChildProcess } from 'child_process'
import { readStore } from './store'
import { notchWindows } from './display'
import { watchForeground } from './mac/helper'

let watcherProcess: ChildProcess | null = null
let lastRawResult = ''
/** Per notch window id: whether it is tucked up out of a browser's way. */
const tucked = new Map<number, boolean>()

/** Browsers, by process name: their tabs and address bar sit right under the notch. */
const BROWSERS = new Set(['chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi'])
/** The same, by macOS bundle id. */
const MAC_BROWSERS = new Set([
  'com.apple.Safari', 'com.google.Chrome', 'com.microsoft.edgemac', 'org.mozilla.firefox', 'com.brave.Browser',
  'company.thebrowser.Browser', 'com.operasoftware.Opera', 'com.vivaldi.Vivaldi',
])

const SCRIPT = (parentPid: number) => `
$code = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class FullscreenCheck {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    public const uint MONITOR_DEFAULTTONEAREST = 2;

    // "fullscreen,monitorLeft,monitorTop,monitorRight,monitorBottom,exe" for
    // the foreground window, or "self" when it is deskNotch (keep the state).
    public static string Foreground() {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return "0,0,0,0,0,";

        StringBuilder className = new StringBuilder(256);
        GetClassName(hwnd, className, 256);
        string cls = className.ToString();
        bool shell = cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd";

        StringBuilder title = new StringBuilder(256);
        GetWindowText(hwnd, title, 256);
        if (title.ToString() == "DeskNotch") return "self";

        IntPtr hMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        MONITORINFO mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(hMonitor, ref mi)) return "0,0,0,0,0,";

        // Fullscreen is F11 or a video's fullscreen: the window exactly covers
        // the monitor and is NOT maximized. A maximized window can cover it too
        // (auto-hide taskbar, or its 8px border overshooting the work area),
        // which is why IsZoomed is checked, not just the rect.
        bool fullscreen = false;
        RECT rect;
        if (!shell && !IsZoomed(hwnd) && GetWindowRect(hwnd, out rect)) {
            fullscreen = rect.Left <= mi.rcMonitor.Left + 2 && rect.Top <= mi.rcMonitor.Top + 2
                && rect.Right >= mi.rcMonitor.Right - 2 && rect.Bottom >= mi.rcMonitor.Bottom - 2;
        }

        string exe = "";
        try {
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            exe = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName;
        } catch {}

        return string.Format("{0},{1},{2},{3},{4},{5}", fullscreen ? 1 : 0,
            mi.rcMonitor.Left, mi.rcMonitor.Top, mi.rcMonitor.Right, mi.rcMonitor.Bottom, exe);
    }
}
"@

Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue

$last = ""
while ($true) {
  if (-not (Get-Process -Id ${parentPid} -ErrorAction SilentlyContinue)) { exit }
  $res = [FullscreenCheck]::Foreground()
  if ($res -ne $last) {
    Write-Output $res
    $last = $res
  }
  Start-Sleep -Milliseconds 300
}
`

/** macOS: the helper reports the frontmost app; turn it into the same line the
 *  Windows watcher prints, with the display's own bounds. */
const watchMac = (on: boolean) =>
  watchForeground(
    on,
    (line) => {
      if ('self' in line) return handleFullscreenChange('self')
      const display = screen.getAllDisplays().find((d) => d.id === line.display) ?? screen.getPrimaryDisplay()
      const { x, y, width, height } = display.bounds
      handleFullscreenChange(`${line.fullscreen ? 1 : 0},${x},${y},${x + width},${y + height},${line.bundle}`)
    },
  )

export function startFullscreenWatch() {
  if (process.platform === 'darwin') return watchMac(true)
  if (process.platform !== 'win32') return

  if (watcherProcess) return

  try {
    watcherProcess = spawn('powershell', ['-NoProfile', '-NonInteractive', '-Command', SCRIPT(process.pid)], {
      windowsHide: true,
    })

    let buffer = ''
    watcherProcess.stdout?.on('data', (chunk: Buffer) => {
      buffer += chunk.toString()
      const lines = buffer.split(/\r?\n/)
      buffer = lines.pop() ?? ''
      for (const line of lines) {
        const trimmed = line.trim()
        if (trimmed) {
          handleFullscreenChange(trimmed)
        }
      }
    })

    watcherProcess.on('error', (err) => {
      console.error('[fullscreen] watcher error:', err)
    })

    watcherProcess.on('exit', () => {
      watcherProcess = null
    })
  } catch (err) {
    console.error('[fullscreen] failed to start watcher:', err)
  }
}

export function stopFullscreenWatch() {
  if (process.platform === 'darwin') return watchMac(false)
  if (watcherProcess) {
    watcherProcess.kill()
    watcherProcess = null
  }
}

/** Starts the watcher when a setting needs it and stops it when none does:
 *  its PowerShell costs ~80 MB, not worth keeping for nothing. */
export function checkAndApplyFullscreenState() {
  const settings = (readStore().settings ?? {}) as Record<string, unknown>
  if (settings.hideOnFullscreen === false && settings.tuckForBrowsers !== true) {
    stopFullscreenWatch()
    lastRawResult = ''
    // Nothing in front on any monitor: every notch shown and untucked.
    handleFullscreenChange('0,0,0,0,0,')
    return
  }
  startFullscreenWatch()
  handleFullscreenChange(lastRawResult)
}

/** Whether this notch is tucked right now, for a renderer that just loaded. */
export const isTucked = (windowId: number) => tucked.get(windowId) ?? false

function handleFullscreenChange(rawResult: string) {
  // deskNotch itself in front (being hovered or clicked): leave everything as it was.
  if (rawResult === 'self') return
  const [flag, l, t, r, b, exe = ''] = rawResult.split(',')
  const monitor = [l, t, r, b].map(Number)
  // A half-written line leaves the notches as they are.
  if ((flag !== '0' && flag !== '1') || monitor.some(isNaN)) return
  lastRawResult = rawResult

  const settings = (readStore().settings ?? {}) as Record<string, unknown>
  const hideOnFullscreen = settings.hideOnFullscreen !== false
  const tuckForBrowsers = settings.tuckForBrowsers === true
  const browser = BROWSERS.has(exe.toLowerCase()) || MAC_BROWSERS.has(exe)

  const displays = screen.getAllDisplays()
  for (const [id, window] of notchWindows()) {
    const display = displays.find((d) => String(d.id) === id)
    // Only the notch on the foreground window's monitor reacts to it.
    let onDisplay = false
    if (display) {
      const { x, y, width, height } = display.bounds
      onDisplay = monitor[0] < x + width && monitor[2] > x && monitor[1] < y + height && monitor[3] > y
    }
    const hide = hideOnFullscreen && flag === '1' && onDisplay
    if (hide && window.isVisible()) window.hide()
    else if (!hide && !window.isVisible()) restoreWindow(window)

    const tuck = tuckForBrowsers && browser && onDisplay && !hide
    if (isTucked(window.id) !== tuck) {
      tucked.set(window.id, tuck)
      window.webContents.send('notch:tucked', tuck)
    }
  }
}
function restoreWindow(window: BrowserWindow) {
  window.showInactive()
  window.setAlwaysOnTop(true, 'screen-saver')
  window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  window.setSkipTaskbar(true)
}