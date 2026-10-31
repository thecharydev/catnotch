import { renderToString } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import SettingsPage from '../pages/settings'

// Regression: the panel branches on the platform, so the pre-render must not
// include it, or Next reports a hydration mismatch at the Calendar row.
describe('Settings page pre-render', () => {
  it('leaves the platform dependent panel out of the server HTML', () => {
    const html = renderToString(<SettingsPage />)
    expect(html).not.toContain('Calendar')
    expect(html).not.toContain('Start at login')
  })
})
