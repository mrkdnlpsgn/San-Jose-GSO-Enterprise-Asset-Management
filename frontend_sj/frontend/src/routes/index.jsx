import { Routes, Route, Navigate } from 'react-router-dom'
import { useSelector } from 'react-redux'
import Login        from '../pages/Auth/Login'
import Dashboard    from '../pages/Dashboard'
import Assets       from '../pages/Assets'
import AssetHistory from '../pages/AssetHistory'
import Maintenance  from '../pages/Maintenance'
import Disposal     from '../pages/Disposal'
import Reports      from '../pages/Reports'
import QRScanner    from '../pages/QRScanner'
import Accounts     from '../pages/Accounts'
import Offices      from '../pages/Offices'
import Categories   from '../pages/Categories'
import DeletedRecords from '../pages/DeletedRecords'
import PrivacyNotice from '../pages/Legal/PrivacyNotice'

function ProtectedRoute({ children }) {
  const isAuthenticated = useSelector((s) => s.auth.isAuthenticated)
  if (!isAuthenticated) return <Navigate to="/login" replace />
  return children
}

function AdminRoute({ children }) {
  const { isAuthenticated, user } = useSelector((s) => s.auth)
  if (!isAuthenticated) return <Navigate to="/login" replace />
  if (user?.role !== 'ADMIN') return <Navigate to="/dashboard" replace />
  return children
}

function PublicRoute({ children }) {
  const isAuthenticated = useSelector((s) => s.auth.isAuthenticated)
  if (isAuthenticated) return <Navigate to="/dashboard" replace />
  return children
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<PublicRoute><Login /></PublicRoute>} />
      <Route path="/privacy" element={<PrivacyNotice />} />

      <Route path="/dashboard"    element={<ProtectedRoute><Dashboard    /></ProtectedRoute>} />
      <Route path="/assets"       element={<ProtectedRoute><Assets       /></ProtectedRoute>} />
      <Route path="/asset-history" element={<ProtectedRoute><AssetHistory /></ProtectedRoute>} />
      <Route path="/maintenance"  element={<ProtectedRoute><Maintenance  /></ProtectedRoute>} />
      <Route path="/disposal"     element={<ProtectedRoute><Disposal     /></ProtectedRoute>} />
      <Route path="/reports"      element={<ProtectedRoute><Reports      /></ProtectedRoute>} />
      <Route path="/qr-scanner"   element={<ProtectedRoute><QRScanner    /></ProtectedRoute>} />
      <Route path="/accounts"     element={<AdminRoute><Accounts          /></AdminRoute>} />
      <Route path="/audit-logs"   element={<ProtectedRoute><Accounts     /></ProtectedRoute>} />
      <Route path="/my-account"   element={<ProtectedRoute><Accounts      /></ProtectedRoute>} />
      <Route path="/offices"      element={<ProtectedRoute><Offices       /></ProtectedRoute>} />
      <Route path="/categories"   element={<ProtectedRoute><Categories    /></ProtectedRoute>} />
      <Route path="/deleted-records" element={<ProtectedRoute><DeletedRecords /></ProtectedRoute>} />

      <Route path="/" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  )
}

export default AppRoutes
