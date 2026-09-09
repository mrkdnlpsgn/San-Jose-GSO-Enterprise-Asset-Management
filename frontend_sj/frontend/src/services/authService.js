import api from './api'

export const login          = (credentials)              => api.post('/auth/login',  credentials)
export const logout         = ()                         => api.post('/auth/logout')

// Completes a login that was interrupted by a mandatory password change (fresh
// account or admin-mediated reset) — proves the temp password, then swaps it.
export const forceChangePassword = ({ identifier, currentPassword, newPassword }) =>
  api.post('/auth/force-change-password', { identifier, currentPassword, newPassword })

// Completes a login that was interrupted by 2FA (every account except admin and
// ict_staff) — proves the emailed code, then issues the session.
export const verifyLoginOtp = (identifier, otp) =>
  api.post('/auth/login/verify-otp', { identifier, otp })

// Step 1: email a one-time code to the account's registered address.
export const requestPasswordReset = (username) =>
  api.post('/auth/forgot-password/request', { username })

// Step 2: confirm the code and set a new password.
export const confirmPasswordReset = (username, otp, newPassword) =>
  api.post('/auth/forgot-password/confirm', { username, otp, newPassword })

// Records that the current user has read the Data Privacy Notice.
export const acknowledgePrivacy = () => api.post('/auth/acknowledge-privacy')
