import React, { useEffect, useState } from 'react'
import Head from 'next/head'
import dynamic from 'next/dynamic'
import { isMac as macNow } from '../components/widgets/SettingsPanel'
import { useSettingsStore } from '../hooks/useSettingsStore'
import { useAiLimits } from '../hooks/useAiLimits'
import { useScreenTime } from '../hooks/useScreenTime'

// Client only: the panel branches on the platform (isMac), which the pre-render can't know.
const SettingsPanel = dynamic(() => import('../components/widgets/SettingsPanel').then((m) => m.SettingsPanel), { ssr: false })

/** The settings window: the same panel the notch used to host, in a frosted
 *  window of its own. Dark always, so the panel's white on dark styles hold. */
export default function SettingsPage() {
  const [settings, setSettings] = useSettingsStore()
  // Read after mount: the platform is unknown while the page is pre-rendered.
  const [isMac, setIsMac] = useState(false)
  useEffect(() => setIsMac(macNow), [])
  const aiLimits = useAiLimits(true)
  const screenTime = useScreenTime(true)

  return (
    <>
      <Head>
        <title>DeskNotch Settings</title>
      </Head>
      {/* The window is transparent so macOS vibrancy and Windows mica show through. */}
      <style jsx global>{`
        html,
        body {
          background: transparent;
          color-scheme: dark;
          overflow: hidden;
        }
      `}</style>
      <div className="h-screen bg-black/35 text-white select-none">
        {/* macOS hides the title bar, so this strip is what drags the window. */}
        {isMac && <div className="fixed inset-x-0 top-0 h-[36px]" style={{ WebkitAppRegion: 'drag' } as React.CSSProperties} />}
        <div className={`h-full p-4 ${isMac ? 'pt-11' : ''}`}>
          <SettingsPanel settings={settings} onChange={setSettings} aiLimits={aiLimits} desktimeInstalled={screenTime.installed} />
        </div>
      </div>
    </>
  )
}
