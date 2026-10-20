import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { Provider } from 'react-redux'
import { store } from './store'
import App from './App.jsx'
// Served from our own origin: a Google Fonts stylesheet held up the first paint by ~0.9s on mobile
import '@fontsource-variable/inter'
import './index.css'

// A redeploy deletes the old page chunks, so a tab opened before it can't load the next page.
// Reload once to pick up the new build (the timestamp stops a reload loop if a chunk is truly gone).
window.addEventListener('vite:preloadError', (e) => {
  try {
    const last = Number(sessionStorage.getItem('chunkReloadAt') || 0)
    if (Date.now() - last < 10000) return
    sessionStorage.setItem('chunkReloadAt', String(Date.now()))
  } catch { /* storage blocked: still reload */ }
  e.preventDefault()
  window.location.reload()
})

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <Provider store={store}>
      <App />
    </Provider>
  </StrictMode>,
)
