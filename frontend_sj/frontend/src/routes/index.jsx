import { lazy, Suspense } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { useSelector } from 'react-redux'
import Login        from '../pages/Auth/Login'

// Every other page is its own chunk, so the login screen doesn't download the whole app
const Dashboard     = lazy(() => import('../pages/Dashboard'))
const Assets        = lazy(() => import('../pages/Assets'))
const AssetHistory  = lazy(() => import('../pages/AssetHistory'))
const Maintenance   = lazy(() => import('../pages/Maintenance'))
const Disposal      = lazy(() => import('../pages/Disposal'))
const Reports       = lazy(() => import('../pages/Reports'))
const TransferAsset = lazy(() => import('../pages/TransferAsset'))
const Accounts      = lazy(() => import('../pages/Accounts'))
const Offices       = lazy(() => import('../pages/Offices'))
const Categories    = lazy(() => import('../pages/Categories'))
const Personnel     = lazy(() => import('../pages/Personnel'))
const DeletedRecords = lazy(() => import('../pages/DeletedRecords'))
const PrivacyNotice = lazy(() => import('../pages/Legal/PrivacyNotice'))

function ProtectedRoute({ children }) {
  const isAuthenticated = useSelector((s) => s.auth.isAuthenticated)
  if (!isAuthenticated) return <Navigate to="/login" replace />
  return children
}

function AdminRoute({ children }) {
  const { isAuthenticated, user } = useSelector((s) => s.auth)
  if (!isAuthenticated) return <Navigate to="/login" replace />
  if (user?.role !== 'ADMIN') return <Navigate to="/home" replace />
  return children
}

function PublicRoute({ children }) {
  const isAuthenticated = useSelector((s) => s.auth.isAuthenticated)
  if (isAuthenticated) return <Navigate to="/home" replace />
  return children
}

function AppRoutes() {
  return (
    <Suspense fallback={null}>
    <Routes>
      <Route path="/login" element={<PublicRoute><Login /></PublicRoute>} />
      <Route path="/privacy" element={<PrivacyNotice />} />

      <Route path="/home"         element={<ProtectedRoute><Dashboard    /></ProtectedRoute>} />
      <Route path="/dashboard"    element={<Navigate to="/home" replace />} />
      <Route path="/assets"       element={<ProtectedRoute><Assets       /></ProtectedRoute>} />
      <Route path="/asset-history" element={<ProtectedRoute><AssetHistory /></ProtectedRoute>} />
      <Route path="/maintenance"  element={<ProtectedRoute><Maintenance  /></ProtectedRoute>} />
      <Route path="/disposal"     element={<ProtectedRoute><Disposal     /></ProtectedRoute>} />
      <Route path="/reports"      element={<ProtectedRoute><Reports      /></ProtectedRoute>} />
      <Route path="/transfer"     element={<ProtectedRoute><TransferAsset /></ProtectedRoute>} />
      {/* The QR Scanner became Transfer Asset (scanning is part of it); keep old links working */}
      <Route path="/qr-scanner"   element={<Navigate to="/transfer" replace />} />
      <Route path="/accounts"     element={<AdminRoute><Accounts          /></AdminRoute>} />
      <Route path="/audit-logs"   element={<AdminRoute><Accounts     /></AdminRoute>} />
      <Route path="/my-account"   element={<ProtectedRoute><Accounts      /></ProtectedRoute>} />
      <Route path="/offices"      element={<AdminRoute><Offices       /></AdminRoute>} />
      <Route path="/categories"   element={<AdminRoute><Categories    /></AdminRoute>} />
      <Route path="/personnel"    element={<AdminRoute><Personnel     /></AdminRoute>} />
      <Route path="/deleted-records" element={<AdminRoute><DeletedRecords /></AdminRoute>} />

      <Route path="/" element={<Navigate to="/home" replace />} />
    </Routes>
    </Suspense>
  )
}

export default AppRoutes
