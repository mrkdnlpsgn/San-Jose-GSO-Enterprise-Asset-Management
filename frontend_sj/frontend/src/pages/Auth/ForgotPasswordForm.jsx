import { useState } from 'react'
import Input from '../../components/common/Input'
import { requestPasswordReset, confirmPasswordReset } from '../../services/authService'
import { PASSWORD_REQUIREMENTS, isPasswordComplex } from '../../utils/passwordPolicy'

const BTN_PRIMARY =
  'w-full h-12 px-5 text-base font-semibold rounded-lg bg-brand-700 text-white hover:bg-brand-800 ' +
  'active:scale-[0.98] transition-all duration-150 focus:outline-none focus:ring-2 focus:ring-brand-500 ' +
  'focus:ring-offset-2 disabled:opacity-70 disabled:cursor-not-allowed'

const LINK =
  'text-sm font-medium text-brand-700 dark:text-brand-400 hover:text-brand-800 dark:hover:text-brand-300 ' +
  'hover:underline underline-offset-2 transition-colors duration-150'

function ErrorBox({ message }) {
  if (!message) return null
  return (
    <div key={message} role="alert"
      className="animate-shake flex items-start gap-2.5 bg-red-50 dark:bg-red-950/50 border border-red-200 dark:border-red-900/60 text-red-700 dark:text-red-400 rounded-lg px-4 py-3 mb-5 text-sm">
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
      </svg>
      {message}
    </div>
  )
}

// Shown in place of the sign-in fields (not a modal). 3 steps: 'request' (enter username, email a
// code) -> 'confirm' (code + new password) -> 'done'. Requiring the emailed code — not just the
// username — is what stops anyone who merely knows a username from taking over the account.
// onBack(username) returns to sign-in, keeping the username typed here.
function ForgotPasswordForm({ initialIdentifier = '', onBack }) {
  const [step, setStep]                       = useState('request')
  const [username, setUsername]               = useState(initialIdentifier.trim())
  const [otp, setOtp]                         = useState('')
  const [newPassword, setNewPassword]         = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [showPassword, setShowPassword]       = useState(false)
  const [loading, setLoading]                 = useState(false)
  const [error, setError]                     = useState('')

  const handleRequest = async (e) => {
    e.preventDefault()
    setError('')
    if (!username.trim()) { setError('Please enter your username.'); return }
    setLoading(true)
    try {
      await requestPasswordReset(username.trim())
      setStep('confirm')
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to request a reset code. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  const handleConfirm = async (e) => {
    e.preventDefault()
    setError('')
    if (!/^\d{6}$/.test(otp.trim())) { setError('Enter the 6-digit code from your email.'); return }
    if (!isPasswordComplex(newPassword)) { setError('New password does not meet the requirements below.'); return }
    if (newPassword !== confirmPassword) { setError('Passwords do not match.'); return }
    setLoading(true)
    try {
      await confirmPasswordReset(username.trim(), otp.trim(), newPassword)
      setStep('done')
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to reset password. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  const back = () => onBack(username.trim())

  return (
    // key={step}: each step rises in, the same way the sign-in fields do
    <div key={step} className="animate-rise-in">
      {step !== 'done' && (
        <button type="button" onClick={back} className={`${LINK} inline-flex items-center gap-1.5 mb-6`}>
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fillRule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clipRule="evenodd" />
          </svg>
          Back to sign in
        </button>
      )}

      {step === 'request' && (
        <>
          <div className="mb-7">
            <h1 className="text-2xl font-bold text-gov-700 dark:text-white tracking-tight">Reset your password</h1>
            <p className="text-base text-slate-600 dark:text-zinc-300 mt-1">
              Enter your username and we'll email a verification code to the address on file.
            </p>
          </div>
          <ErrorBox message={error} />
          <form onSubmit={handleRequest} noValidate>
            <div className="mb-6">
              <Input
                id="reset-username"
                label="Username"
                type="text"
                autoComplete="username"
                autoFocus
                placeholder="Enter your username"
                value={username}
                onChange={(e) => { setUsername(e.target.value); setError('') }}
                className="!text-base py-3"
                startIcon={
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z" clipRule="evenodd" />
                  </svg>
                }
              />
            </div>
            <button type="submit" disabled={loading} className={BTN_PRIMARY}>
              {loading ? 'Sending…' : 'Send Verification Code'}
            </button>
            <p className="mt-4 text-sm text-slate-600 dark:text-zinc-400">
              A new code can be requested once every 15 minutes per account. No email on file? Ask the system administrator to reset your password.
            </p>
          </form>
        </>
      )}

      {step === 'confirm' && (
        <>
          <div className="mb-7">
            <h1 className="text-2xl font-bold text-gov-700 dark:text-white tracking-tight">Enter the code</h1>
            <p className="text-base text-slate-600 dark:text-zinc-300 mt-1">
              If <span className="font-semibold">{username.trim()}</span> has an email on file, a 6-digit code was sent to it.
            </p>
          </div>
          <ErrorBox message={error} />
          <form onSubmit={handleConfirm} noValidate className="space-y-5">
            <Input
              id="reset-code"
              label="Verification code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              autoFocus
              maxLength={6}
              placeholder="6-digit code"
              value={otp}
              onChange={(e) => { setOtp(e.target.value.replace(/\D/g, '')); setError('') }}
              className="!text-lg py-3 tracking-[0.3em] text-center font-mono"
            />

            {otp.length === 6 && (
              <div className="space-y-5 animate-rise-in">
                <div>
                  <Input
                    id="reset-new-password"
                    label="New password"
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="new-password"
                    autoFocus
                    placeholder="Enter new password"
                    value={newPassword}
                    onChange={(e) => { setNewPassword(e.target.value); setError('') }}
                    className="!text-base py-3 pr-20"
                    adornmentClassName="pr-1.5"
                    endAdornment={
                      <button type="button" onClick={() => setShowPassword((v) => !v)} aria-pressed={showPassword}
                        className="h-9 px-3 rounded-md text-sm font-semibold text-slate-700 dark:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150">
                        {showPassword ? 'Hide' : 'Show'}
                      </button>
                    }
                  />
                  {newPassword && (
                    <ul className="mt-2 space-y-1">
                      {PASSWORD_REQUIREMENTS.map(({ key, label, test }) => {
                        const met = test(newPassword)
                        return (
                          <li key={key} className={`flex items-center gap-1.5 text-sm transition-colors ${met ? 'text-emerald-700 dark:text-emerald-400' : 'text-slate-500 dark:text-zinc-400'}`}>
                            {met
                              ? <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" /></svg>
                              : <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" /></svg>
                            }
                            {label}
                          </li>
                        )
                      })}
                    </ul>
                  )}
                </div>

                <Input
                  id="reset-confirm-password"
                  label="Confirm new password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="new-password"
                  placeholder="Re-enter new password"
                  value={confirmPassword}
                  onChange={(e) => { setConfirmPassword(e.target.value); setError('') }}
                  className="!text-base py-3"
                />

                <button type="submit" disabled={loading} className={BTN_PRIMARY}>
                  {loading ? 'Resetting…' : 'Reset Password'}
                </button>
              </div>
            )}

            <button type="button" className={LINK}
              onClick={() => { setStep('request'); setOtp(''); setNewPassword(''); setConfirmPassword(''); setError('') }}>
              Didn't get a code? Try again or use a different username
            </button>
          </form>
        </>
      )}

      {step === 'done' && (
        <div className="text-center" role="status">
          <div className="flex items-center justify-center w-14 h-14 rounded-full bg-emerald-100 dark:bg-emerald-900/30 mx-auto animate-seal-in">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-7 w-7 text-emerald-600" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
          </div>
          <h1 className="mt-5 text-2xl font-bold text-gov-700 dark:text-white tracking-tight">Password reset</h1>
          <p className="mt-1 mb-7 text-base text-slate-600 dark:text-zinc-300">
            Your password has been updated. You can now sign in with your new password.
          </p>
          <button type="button" onClick={back} className={BTN_PRIMARY} autoFocus>
            Back to Sign In
          </button>
        </div>
      )}
    </div>
  )
}

export default ForgotPasswordForm
