import { useSelector } from 'react-redux'
import { BrowserRouter } from 'react-router-dom'
import { ThemeProvider } from './context/ThemeContext'
import { ToastProvider } from './context/ToastContext'
import AppRoutes from './routes'
import RealtimeSync from './components/RealtimeSync'
import SessionGuard from './components/SessionGuard'
import ActionOtpPrompt from './components/common/ActionOtpPrompt'

function AppContent() {
  const isAuthenticated = useSelector((s) => s.auth.isAuthenticated)
  return (
    <>
      {isAuthenticated && <RealtimeSync />}
      {isAuthenticated && <SessionGuard />}
      {isAuthenticated && <ActionOtpPrompt />}
      <AppRoutes />
    </>
  )
}

function App() {
  return (
    <ThemeProvider>
      <ToastProvider>
        {/* startTransition keeps the current page on screen while the next page's chunk loads */}
        <BrowserRouter future={{ v7_startTransition: true }}>
          <AppContent />
        </BrowserRouter>
      </ToastProvider>
    </ThemeProvider>
  )
}

export default App
