import { botAvatarPalette } from 'bot-avatars'
import type { Avatar } from '../components/widgets/SettingsPanel'

/** Catppuccin's dark flavours: the notch's fill (base) and a few accents. */
export type Flavor = 'mocha' | 'macchiato' | 'frappe'

export const FLAVORS: Record<Flavor, { label: string; base: string; accents: Record<string, string> }> = {
  mocha: {
    label: 'Mocha',
    base: '#1e1e2e',
    accents: { Mauve: '#cba6f7', Blue: '#89b4fa', Sapphire: '#74c7ec', Green: '#a6e3a1', Peach: '#fab387', Pink: '#f5c2e7', Red: '#f38ba8', Text: '#cdd6f4' },
  },
  macchiato: {
    label: 'Macchiato',
    base: '#24273a',
    accents: { Mauve: '#c6a0f6', Blue: '#8aadf4', Sapphire: '#7dc4e4', Green: '#a6da95', Peach: '#f5a97f', Pink: '#f5bde6', Red: '#ed8796', Text: '#cad3f5' },
  },
  frappe: {
    label: 'Frappé',
    base: '#303446',
    accents: { Mauve: '#ca9ee6', Blue: '#8caaee', Sapphire: '#85c1dc', Green: '#a6d189', Peach: '#ef9f76', Pink: '#f4b8e4', Red: '#e78284', Text: '#c6d0f5' },
  },
}

export const DEFAULT_FLAVOR: Flavor = 'mocha'
export const DEFAULT_OPACITY = 0.7
export const DEFAULT_BLUR = 20

const rgba = (hex: string, alpha: number) => {
  const n = parseInt(hex.slice(1), 16)
  return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`
}

export interface NotchTheme {
  notchFlavor?: Flavor
  /** A custom fill, replacing the flavour's base. */
  notchColor?: string
  /** The edge highlight; the flavour's Mauve when unset. */
  notchAccent?: string
  notchOpacity?: number
  /** Glass blur radius in px, as Ghostty's background-blur-radius. */
  notchBlur?: number
}

/** Puts the notch's look on the page as CSS variables the Backdrop reads. */
export const applyNotchTheme = (t: NotchTheme) => {
  const flavor = FLAVORS[t.notchFlavor ?? DEFAULT_FLAVOR] ?? FLAVORS[DEFAULT_FLAVOR]
  const root = document.documentElement.style
  root.setProperty('--notch-fill', rgba(t.notchColor ?? flavor.base, t.notchOpacity ?? DEFAULT_OPACITY))
  root.setProperty('--notch-rim', rgba(t.notchAccent ?? flavor.accents.Mauve, 0.5))
  root.setProperty('--notch-blur', `${t.notchBlur ?? DEFAULT_BLUR}px`)
  root.setProperty('--notch-blur-small', `${(t.notchBlur ?? DEFAULT_BLUR) / 2}px`)
}

/** The cat's coat: the flavour's accent by name, Mauve when missing or unknown. */
export const catCoat = (flavor: Flavor | undefined, accent?: string) => {
  const accents = (FLAVORS[flavor ?? DEFAULT_FLAVOR] ?? FLAVORS[DEFAULT_FLAVOR]).accents
  return accents[accent ?? 'Mauve'] ?? accents.Mauve
}

/** The companion's own colour: the coat for the cat, the bot's palette, or white for a photo. */
export const avatarAccent = (s: { avatar: Avatar; catAccent?: string; notchFlavor?: Flavor }) =>
  s.avatar === 'photo' ? '#ffffff' : s.avatar === 'catppuccin' ? catCoat(s.notchFlavor, s.catAccent) : botAvatarPalette[s.avatar]
