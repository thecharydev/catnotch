import { useEffect, useState } from 'react'

export interface HardwareNotch {
  w: number
  h: number
}

/** The real notch's size on this display (macOS), or null for the pill. */
export function useHardwareNotch(): HardwareNotch | null {
  const [notch, setNotch] = useState<HardwareNotch | null>(null)

  useEffect(() => {
    const bridge = window.bridge
    if (!bridge?.invoke) return
    bridge.invoke<HardwareNotch | null>('notch:hardware').then(setNotch).catch(() => {})
    return bridge.on<HardwareNotch | null>('notch:hardware', setNotch)
  }, [])

  return notch
}
