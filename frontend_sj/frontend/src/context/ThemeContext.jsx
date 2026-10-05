import { createContext, useContext, useEffect, useState } from 'react'

// Text size is a per-device preference (an employee with weaker eyesight sets it once on
// their own PC). It scales the root font size, and since the UI is sized in rem, text,
// buttons, icons and spacing all grow together — like browser zoom, but remembered.
export const TEXT_SIZES = [
  { id: 'normal',  label: 'Normal',  scale: 100 },
  { id: 'large',   label: 'Large',   scale: 112.5 },
  { id: 'larger',  label: 'Larger',  scale: 125 },
  { id: 'largest', label: 'Largest', scale: 137.5 },
]
const TEXT_SIZE_KEY = 'ict-text-size'

function readTextSize() {
  try {
    const saved = localStorage.getItem(TEXT_SIZE_KEY)
    if (TEXT_SIZES.some((s) => s.id === saved)) return saved
  } catch { /* storage blocked — fall back to normal */ }
  return 'normal'
}

function applyTextSize(id) {
  const size = TEXT_SIZES.find((s) => s.id === id) ?? TEXT_SIZES[0]
  document.documentElement.style.fontSize = size.scale === 100 ? '' : `${size.scale}%`
}

const ThemeContext = createContext({ isDark: false, toggle: () => {}, textSize: 'normal', setTextSize: () => {} })

export function ThemeProvider({ children }) {
  const [isDark, setIsDark] = useState(() => {
    // Always open in light mode; user can toggle dark within the session
    document.documentElement.classList.remove('dark')
    return false
  })

  const [textSize, setTextSize] = useState(() => {
    const id = readTextSize()
    applyTextSize(id) // before first paint, so the page doesn't jump
    return id
  })

  useEffect(() => {
    document.documentElement.classList.toggle('dark', isDark)
    localStorage.setItem('ict-theme', isDark ? 'dark' : 'light')
  }, [isDark])

  useEffect(() => {
    applyTextSize(textSize)
    try { localStorage.setItem(TEXT_SIZE_KEY, textSize) } catch { /* not remembered, still applied */ }
  }, [textSize])

  return (
    <ThemeContext.Provider value={{ isDark, toggle: () => setIsDark((p) => !p), textSize, setTextSize }}>
      {children}
    </ThemeContext.Provider>
  )
}

export const useTheme = () => useContext(ThemeContext)
