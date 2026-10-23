import { createSlice } from '@reduxjs/toolkit'

// User info (non-sensitive) is kept in sessionStorage for page-refresh persistence.
// The JWT itself lives only in an HttpOnly cookie - inaccessible to JavaScript.
const savedUser = (() => {
  try { return JSON.parse(sessionStorage.getItem('auth-user') || 'null') }
  catch { return null }
})()

const authSlice = createSlice({
  name: 'auth',
  initialState: {
    user:            savedUser,
    isAuthenticated: !!savedUser,
    loading:         false,
    error:           null,
  },
  reducers: {
    setCredentials: (state, action) => {
      state.user            = action.payload.user
      state.isAuthenticated = true
      sessionStorage.setItem('auth-user', JSON.stringify(action.payload.user))
    },
    logout: (state) => {
      state.user            = null
      state.isAuthenticated = false
      sessionStorage.removeItem('auth-user')
    },
    // Merges partial fields into the stored user without a full re-login - used
    // after acknowledging the Data Privacy Notice to update privacyAcknowledgedAt.
    updateUser: (state, action) => {
      state.user = { ...state.user, ...action.payload }
      sessionStorage.setItem('auth-user', JSON.stringify(state.user))
    },
  },
})

export const { setCredentials, logout, updateUser } = authSlice.actions
export default authSlice.reducer
