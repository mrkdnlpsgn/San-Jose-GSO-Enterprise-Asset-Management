import { useSelector } from 'react-redux'
import { BrowserRouter } from 'react-router-dom'
import { ThemeProvider } from './context/ThemeContext'
import { ToastProvider } from './context/ToastContext'
import AppRoutes from './routes'
import RealtimeSync from './components/RealtimeSync'
import SessionGuard from './components/SessionGuard'

function AppContent() {
  const isAuthenticated = useSelector((s) => s.auth.isAuthenticated)
  return (
    <>
      {isAuthenticated && <RealtimeSync />}
      {isAuthenticated && <SessionGuard />}
      <AppRoutes />
    </>
  )
}

function App() {
  return (
    <ThemeProvider>
      <ToastProvider>
        <BrowserRouter>
          <AppContent />
        </BrowserRouter>
      </ToastProvider>
    </ThemeProvider>
  )
}

export default App
