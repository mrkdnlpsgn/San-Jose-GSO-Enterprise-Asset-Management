import { useState } from 'react'
import Input from '../../components/common/Input'
import { PASSWORD_REQUIREMENTS, isPasswordComplex } from '../../utils/passwordPolicy'

// Shown in place of the login form when the backend reports mustChangePassword —
// a fresh account or an admin-mediated reset. Re-collects the temp password
// (never persisted client-side) alongside the new one, then hands both to the
// caller, which exchanges them for a real session via /auth/force-change-password.
function ForceChangePasswordForm({ identifier, currentPassword, onSubmit }) {
  const [newPassword, setNewPassword] = useState('')
  const [confirm, setConfirm]         = useState('')
  const [error, setError]             = useState('')
  const [loading, setLoading]         = useState(false)

  const complexityMet = isPasswordComplex(newPassword)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    if (!complexityMet) { setError('New password does not meet the requirements below.'); return }
    if (newPassword !== confirm) { setError('Passwords do not match.'); return }
    setLoading(true)
    try {
      await onSubmit({ identifier, currentPassword, newPassword })
    } catch (err) {
      setError(err?.response?.data?.message || 'Failed to change password. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="w-full max-w-sm animate-rise-in">
      <div className="mb-7">
        <h1 className="text-2xl font-bold text-slate-900 dark:text-white tracking-tight">Set a new password</h1>
        <p className="text-sm text-slate-500 dark:text-zinc-400 mt-1">
          This account is using a temporary password. Choose a new one to continue.
        </p>
      </div>

      {error && (
        <div
          role="alert"
          className="flex items-start gap-2.5 bg-red-50 dark:bg-red-950/50 border border-red-200 dark:border-red-900/60 text-red-600 dark:text-red-400 rounded-lg px-4 py-3 mb-5 text-sm"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit} noValidate>
        <div className="mb-4">
          <Input
            id="new-password"
            label="New Password"
            type="password"
            autoComplete="new-password"
            autoFocus
            placeholder="Enter new password"
            value={newPassword}
            onChange={(e) => { setNewPassword(e.target.value); setError('') }}
            required
          />
          {newPassword && (
            <ul className="mt-1.5 space-y-0.5">
              {PASSWORD_REQUIREMENTS.map(({ key, label, test }) => {
                const met = test(newPassword)
                return (
                  <li key={key} className={`flex items-center gap-1.5 text-xs transition-colors ${met ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-400 dark:text-zinc-500'}`}>
                    {met
                      ? <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" /></svg>
                      : <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" /></svg>
                    }
                    {label}
                  </li>
                )
              })}
            </ul>
          )}
        </div>

        <div className="mb-6">
          <Input
            id="confirm-new-password"
            label="Confirm New Password"
            type="password"
            autoComplete="new-password"
            placeholder="Re-enter new password"
            value={confirm}
            onChange={(e) => { setConfirm(e.target.value); setError('') }}
            required
          />
        </div>

        <button
          type="submit"
          disabled={loading}
          className="w-full py-2.5 px-5 text-sm font-semibold rounded-lg bg-brand-700 text-white hover:bg-brand-800 active:scale-[0.98] transition-all duration-150 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-zinc-950 disabled:opacity-40 disabled:cursor-not-allowed disabled:active:scale-100"
        >
          {loading ? (
            <span className="flex items-center justify-center gap-2">
              <svg className="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
              </svg>
              Saving...
            </span>
          ) : 'Set Password & Sign In'}
        </button>
      </form>
    </div>
  )
}

export default ForceChangePasswordForm
