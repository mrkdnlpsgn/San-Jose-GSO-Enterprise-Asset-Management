import { useCallback } from 'react'
import { useSelector, useDispatch } from 'react-redux'
import { useNavigate } from 'react-router-dom'
import { setCredentials, logout, updateUser } from '../store/slices/authSlice'
import { login as loginApi, logout as logoutApi, forceChangePassword as forceChangePasswordApi, verifyLoginOtp as verifyLoginOtpApi, acknowledgePrivacy as acknowledgePrivacyApi } from '../services/authService'

export function useAuth() {
  const dispatch  = useDispatch()
  const navigate  = useNavigate()
  const { user, isAuthenticated } = useSelector((state) => state.auth)

  // Correct credentials but a temp password or 2FA pending return
  // { mustChangePassword: true } / { requiresTwoFactor: true } instead of a
  // session — the caller (Login) must collect a new password / emailed code
  // before this resolves.
  const login = useCallback(async ({ identifier, password }) => {
    const { data } = await loginApi({ identifier, password })
    if (data.mustChangePassword || data.requiresTwoFactor) return data
    // Backend sets the JWT as an HttpOnly cookie — only user info is in the response body
    dispatch(setCredentials({ user: data.user }))
    return data
  }, [dispatch])

  const completeForcedPasswordChange = useCallback(async ({ identifier, currentPassword, newPassword }) => {
    const { data } = await forceChangePasswordApi({ identifier, currentPassword, newPassword })
    dispatch(setCredentials({ user: data.user }))
  }, [dispatch])

  const completeLoginOtp = useCallback(async ({ identifier, otp }) => {
    const { data } = await verifyLoginOtpApi(identifier, otp)
    dispatch(setCredentials({ user: data.user }))
  }, [dispatch])

  const signOut = useCallback(async () => {
    try { await logoutApi() } catch {} // clears the HttpOnly cookie on the backend
    dispatch(logout())
    navigate('/login', { replace: true })
  }, [dispatch, navigate])

  const acknowledgePrivacy = useCallback(async () => {
    const { data } = await acknowledgePrivacyApi()
    dispatch(updateUser({ privacyAcknowledgedAt: data.privacyAcknowledgedAt }))
  }, [dispatch])

  return { user, isAuthenticated, login, completeForcedPasswordChange, completeLoginOtp, signOut, acknowledgePrivacy }
}
