import { useState, useEffect, useRef } from 'react'
import { useDispatch } from 'react-redux'
import { updateUser as updateAuthUser } from '../../store/slices/authSlice'
import { useToast } from '../../context/ToastContext'
import { useAuth } from '../../hooks/useAuth'
import Button from '../../components/common/Button'
import Badge from '../../components/common/Badge'
import Input from '../../components/common/Input'
import UserAvatar from '../../components/common/UserAvatar'
import Modal from '../../components/common/Modal'
import { changePassword, uploadAvatar, removeAvatar, getMyOverview, setMyTwoFactor, forgetMyDevices, updateMyDetails } from '../../services/userService'
import { toSquareJpeg } from '../../utils/squareImage'
import { PASSWORD_REQUIREMENTS, isPasswordComplex } from '../../utils/passwordPolicy'
import { roleLabel } from '../../utils/roles'

const CARD = 'bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800'
const CARD_TITLE = 'text-base font-semibold text-gov-700 dark:text-white'

// The server's clock (and MySQL NOW()) run in UTC and send timestamps without a zone, e.g.
// "2026-10-07T04:12:00" - read them as UTC, or every time shows 8 hours early in Manila.
function serverTime(value) {
  if (!value) return null
  const s = String(value)
  return new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + 'Z')
}

function fmtDate(value) {
  if (!value) return 'N/A'
  return serverTime(value).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', year: 'numeric', month: 'long', day: 'numeric' })
}

// "3 minutes ago", "yesterday", "2 weeks ago" - falls back to the date after a month.
function timeAgo(value) {
  if (!value) return ''
  const then = serverTime(value)
  const secs = Math.round((then - Date.now()) / 1000)
  const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' })
  const steps = [[60, 'second'], [60, 'minute'], [24, 'hour'], [7, 'day'], [4.35, 'week']]
  let n = secs
  for (const [size, unit] of steps) {
    if (Math.abs(n) < size) return rtf.format(Math.round(n), unit)
    n /= size
  }
  return fmtDate(value)
}

const ACTION_LABELS = {
  USER_2FA_ENABLED:  '2-step verification turned on',
  USER_2FA_DISABLED: '2-step verification turned off',
  PROFILE_PICTURE_CHANGED: 'Profile picture changed',
  PROFILE_PICTURE_REMOVED: 'Profile picture removed',
  AI_RECOMMENDATION_GENERATED: 'AI recommendation generated',
}

// ASSET_UPDATED -> "Asset updated"
function actionLabel(action) {
  if (ACTION_LABELS[action]) return ACTION_LABELS[action]
  const s = (action || '').toLowerCase().replace(/_/g, ' ')
  return s.charAt(0).toUpperCase() + s.slice(1)
}

const STRENGTH = [
  { min: 0, label: 'Too weak',  bar: 'bg-red-500',     text: 'text-red-600 dark:text-red-400' },
  { min: 3, label: 'Almost there', bar: 'bg-amber-500', text: 'text-amber-700 dark:text-amber-400' },
  { min: 5, label: 'Meets all requirements', bar: 'bg-emerald-500', text: 'text-emerald-700 dark:text-emerald-400' },
]

function Check({ met }) {
  // key={met}: the icon re-mounts when the state flips, so the new one pops in
  return met ? (
    <svg key="met" xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 flex-shrink-0 animate-scale-in" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
    </svg>
  ) : (
    <span key="unmet" className="h-4 w-4 flex-shrink-0 rounded-full border-2 border-slate-300 dark:border-zinc-600" aria-hidden="true" />
  )
}

function ShowHide({ shown, onToggle, controls }) {
  return (
    <button type="button" onClick={onToggle} aria-pressed={shown} aria-controls={controls}
      className="h-8 px-2.5 rounded-md text-sm font-semibold text-slate-600 dark:text-zinc-300 hover:bg-slate-100 dark:hover:bg-zinc-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150">
      {shown ? 'Hide' : 'Show'}
    </button>
  )
}

function DetailRow({ label, children }) {
  return (
    <div className="flex flex-col gap-0.5 min-w-0">
      <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">{label}</dt>
      <dd className="text-sm text-slate-800 dark:text-zinc-100 break-words">{children}</dd>
    </div>
  )
}

// Every card on the page opens the same way: an icon tile, the title, one line on what it is
// for, and (optionally) a status or button on the right.
const ICONS = {
  details:  <path fillRule="evenodd" d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z" clipRule="evenodd" />,
  password: <path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" />,
  twoStep:  <path fillRule="evenodd" d="M2.166 4.999A11.954 11.954 0 0010 1.944 11.954 11.954 0 0017.834 5c.11.65.166 1.32.166 2.001 0 5.225-3.34 9.67-8 11.317C5.34 16.67 2 12.225 2 7c0-.682.057-1.35.166-2.001zm11.541 3.708a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />,
  activity: <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" />,
}

function CardHeader({ icon, title, description, action }) {
  return (
    <div className="flex items-start gap-3 mb-5">
      <span className="w-10 h-10 rounded-lg bg-brand-500/10 text-brand-700 dark:text-brand-400 flex items-center justify-center flex-shrink-0">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">{ICONS[icon]}</svg>
      </span>
      <div className="flex-1 min-w-0">
        <h3 className={CARD_TITLE}>{title}</h3>
        {description && <p className="text-sm text-slate-600 dark:text-zinc-400 mt-0.5">{description}</p>}
      </div>
      {action && <div className="flex-shrink-0">{action}</div>}
    </div>
  )
}

function FormError({ children }) {
  if (!children) return null
  return (
    <div key={children} role="alert"
      className="animate-shake flex items-start gap-2.5 bg-red-50 dark:bg-red-950/50 border border-red-200 dark:border-red-900/60 text-red-700 dark:text-red-400 rounded-lg px-4 py-3 text-sm mb-5">
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
      </svg>
      {children}
    </div>
  )
}

// The secondary action next to a card's main button (Clear, Cancel)
function TextAction({ onClick, children }) {
  return (
    <button type="button" onClick={onClick}
      className="text-sm font-medium text-slate-500 dark:text-zinc-400 hover:text-slate-800 dark:hover:text-zinc-200 hover:underline underline-offset-2">
      {children}
    </button>
  )
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

// Your full name and email: shown, or edited in place. Saving asks for the current password in
// a small window first; the username (used to sign in) and the office stay with the admin.
function AccountDetailsCard({ user, overview, onSaved }) {
  const toast    = useToast()
  const dispatch = useDispatch()
  const [editing, setEditing]   = useState(false)
  const [form, setForm]         = useState({ fullName: '', email: '' })
  const [errors, setErrors]     = useState({})
  const [error, setError]       = useState('')
  const [confirming, setConfirming] = useState(false)
  const [password, setPassword] = useState('')
  const [pwError, setPwError]   = useState('')
  const [saving, setSaving]     = useState(false)

  const email      = overview?.email || ''
  const officeName = overview?.officeName || user?.officeName
  const changed    = editing && (form.fullName.trim() !== (user?.fullName || '') || form.email.trim() !== email)

  const startEdit = () => {
    setForm({ fullName: user?.fullName || '', email })
    setErrors({}); setError(''); setEditing(true)
  }
  const cancel = () => { setEditing(false); setErrors({}); setError('') }
  const set = (key) => (e) => {
    setForm((f) => ({ ...f, [key]: e.target.value }))
    setErrors((x) => ({ ...x, [key]: undefined })); setError('')
  }

  const review = (e) => {
    e.preventDefault()
    const errs = {}
    if (!form.fullName.trim()) errs.fullName = 'Enter your full name.'
    if (form.email.trim() && !EMAIL_RE.test(form.email.trim())) errs.email = 'Enter a valid email address, like name@example.com.'
    if (!form.email.trim() && overview?.twoFactorEnabled) errs.email = '2-step verification sends its code here. Turn it off before removing the email.'
    setErrors(errs)
    if (Object.keys(errs).length) return
    setPassword(''); setPwError(''); setConfirming(true)
  }

  const save = async (e) => {
    e.preventDefault()
    if (!password) { setPwError('Enter your current password.'); return }
    setSaving(true)
    try {
      const { data } = await updateMyDetails({ fullName: form.fullName.trim(), email: form.email.trim(), currentPassword: password })
      dispatch(updateAuthUser({ fullName: data.fullName }))
      onSaved(data.email || null)
      setConfirming(false); setEditing(false)
      toast.show('Account details saved.', 'success')
    } catch (err) {
      const msg = err.response?.data?.message || 'Could not save your details.'
      // a wrong password is fixed in the window; anything else is about the details themselves
      if (/password/i.test(msg)) setPwError(msg)
      else { setConfirming(false); setError(msg) }
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className={`${CARD} p-5 sm:p-6 animate-rise-in [animation-delay:80ms]`}>
      <CardHeader icon="details" title="Account details"
        description={editing ? 'Change your name or email, then confirm with your password.' : 'Your name and email as the system shows them.'}
        action={!editing && (
          <Button type="button" size="sm" variant="secondary" onClick={startEdit} disabled={overview === null}>Edit</Button>
        )} />

      <FormError>{error}</FormError>

      {editing ? (
        <form onSubmit={review} noValidate className="space-y-5 animate-fade-in">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            <Input id="details-name" label="Full name" autoComplete="name" maxLength={100} autoFocus
              value={form.fullName} onChange={set('fullName')} error={errors.fullName} className="!text-base py-3" />
            <Input id="details-email" label="Email" type="email" autoComplete="email" maxLength={100}
              placeholder="name@example.com" value={form.email} onChange={set('email')} error={errors.email}
              hint="Password reset and sign-in codes are sent here." className="!text-base py-3" />
          </div>
          <dl className="grid grid-cols-1 md:grid-cols-2 gap-5 rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-950/40 px-4 py-3.5">
            <DetailRow label="Username"><span className="font-mono">{user?.username}</span></DetailRow>
            <DetailRow label="Office">{officeName || <span className="text-slate-500 dark:text-zinc-400">Not assigned</span>}</DetailRow>
            <p className="md:col-span-2 text-sm text-slate-600 dark:text-zinc-400">Only an administrator can change these.</p>
          </dl>
          <div className="flex flex-wrap items-center gap-3 pt-1">
            <Button type="submit" size="md" disabled={!changed}>Save changes</Button>
            <TextAction onClick={cancel}>Cancel</TextAction>
          </div>
        </form>
      ) : (
        <dl className="grid grid-cols-1 md:grid-cols-2 gap-x-5 gap-y-4">
          <DetailRow label="Full name">{user?.fullName || user?.username}</DetailRow>
          <DetailRow label="Username"><span className="font-mono">{user?.username}</span></DetailRow>
          <DetailRow label="Email">
            {overview === null ? <span className="inline-block h-4 w-40 rounded bg-slate-200 dark:bg-zinc-700 animate-pulse" />
              : email || (
                <span className="text-amber-700 dark:text-amber-400">
                  None on file. Add one with Edit so you can reset a forgotten password.
                </span>
              )}
          </DetailRow>
          <DetailRow label="Office">{officeName || <span className="text-slate-500 dark:text-zinc-400">Not assigned</span>}</DetailRow>
        </dl>
      )}

      {confirming && (
        <Modal title="Confirm it's you" subtitle="Enter your current password to save your account details." size="md"
          onClose={() => !saving && setConfirming(false)}>
          <form onSubmit={save} noValidate className="space-y-4">
            <Input id="details-password" label="Current password" type="password" autoComplete="current-password" autoFocus
              value={password} onChange={(e) => { setPassword(e.target.value); setPwError('') }} error={pwError}
              className="!text-base py-3" />
            <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
              <Button type="button" variant="secondary" size="md" onClick={() => setConfirming(false)} disabled={saving}>Cancel</Button>
              <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : 'Confirm and save'}</Button>
            </div>
          </form>
        </Modal>
      )}
    </section>
  )
}

// Turn the emailed sign-in code on or off for your own account. Turning it off asks for the
// current password first, inline.
function TwoStepCard({ overview, onChange }) {
  const toast = useToast()
  const { signOut } = useAuth()
  const [confirmForget, setConfirmForget] = useState(false)
  const [forgetting, setForgetting] = useState(false)

  const forgetDevices = async () => {
    setForgetting(true)
    setError('')
    try {
      await forgetMyDevices()
      await signOut({ reason: 'signed-out-everywhere' })
    } catch (err) {
      setError(err.response?.data?.message || 'Could not forget remembered computers.')
      setForgetting(false)
    }
  }
  const [asking, setAsking]   = useState(false)
  const [password, setPassword] = useState('')
  const [busy, setBusy]       = useState(false)
  const [error, setError]     = useState('')

  if (!overview) {
    return (
      <section className={`${CARD} p-5 sm:p-6 animate-rise-in [animation-delay:170ms]`}>
        <CardHeader icon="twoStep" title="2-step verification" />
        <div className="h-16 rounded bg-slate-100 dark:bg-zinc-800 animate-pulse" />
      </section>
    )
  }

  const on = Boolean(overview.twoFactorEnabled)
  const hasEmail = Boolean(overview.email)

  const save = async (enabled) => {
    setBusy(true)
    setError('')
    try {
      const { data } = await setMyTwoFactor(enabled, enabled ? undefined : password)
      onChange(data.twoFactorEnabled)
      setAsking(false)
      setPassword('')
      toast.show(enabled ? '2-step verification is now on.' : '2-step verification is now off.', 'success')
    } catch (err) {
      setError(err.response?.data?.message || 'Could not change 2-step verification.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className={`${CARD} p-5 sm:p-6 animate-rise-in [animation-delay:170ms]`}>
      <CardHeader icon="twoStep" title="2-step verification"
        action={
          <span key={String(on)}
            className={`inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-full animate-scale-in ${on
              ? 'text-emerald-700 dark:text-emerald-300 bg-emerald-50 dark:bg-emerald-400/10 ring-1 ring-emerald-200 dark:ring-emerald-800'
              : 'text-slate-600 dark:text-zinc-300 bg-slate-100 dark:bg-zinc-800 ring-1 ring-slate-200 dark:ring-zinc-700'}`}>
            <span className={`w-1.5 h-1.5 rounded-full ${on ? 'bg-emerald-500' : 'bg-slate-400'}`} />
            {on ? 'On' : 'Off'}
          </span>
        } />
      <p className="text-sm text-slate-600 dark:text-zinc-400 -mt-2 mb-5">
        {on
          ? <>Signing in needs your password <span className="font-semibold">and</span> a 6-digit code sent to <span className="font-medium text-slate-800 dark:text-zinc-200 break-all">{overview.email}</span>.</>
          : "Add a second check: after your password, you enter a 6-digit code sent to your email. Someone who learns your password still can't sign in."}
      </p>

      <FormError>{error}</FormError>

      {!on && (
        <div>
          <Button type="button" size="md" onClick={() => save(true)} disabled={busy || !hasEmail}>
            {busy ? 'Turning on…' : 'Turn on'}
          </Button>
          {!hasEmail && (
            <p className="mt-2 text-sm text-amber-700 dark:text-amber-400">
              Needs an email address on your account. Add one under Account details.
            </p>
          )}
        </div>
      )}

      {on && !asking && !confirmForget && (
        <div className="flex flex-wrap gap-x-5 gap-y-2">
          <button type="button" onClick={() => { setConfirmForget(true); setError('') }}
            className="text-sm font-medium text-brand-700 dark:text-brand-400 hover:underline underline-offset-2">
            Forget remembered computers…
          </button>
          <button type="button" onClick={() => { setAsking(true); setError('') }}
            className="text-sm font-medium text-slate-600 dark:text-zinc-300 hover:text-red-600 dark:hover:text-red-400 hover:underline underline-offset-2">
            Turn off…
          </button>
        </div>
      )}

      {on && confirmForget && (
        <div className="rounded-lg border border-amber-200 dark:border-amber-500/30 bg-amber-50 dark:bg-amber-500/10 px-3.5 py-3 animate-rise-in">
          <p className="text-sm text-amber-900 dark:text-amber-200">
            Every computer where you ticked "Don't ask for a code" will ask for one again. This also
            signs you out everywhere, including here.
          </p>
          <div className="mt-3 flex flex-wrap items-center gap-3">
            <Button type="button" size="md" variant="danger" onClick={forgetDevices} disabled={forgetting}>
              {forgetting ? 'Signing out…' : 'Forget and sign out'}
            </Button>
            <TextAction onClick={() => setConfirmForget(false)}>Cancel</TextAction>
          </div>
        </div>
      )}

      {on && asking && (
        <form className="space-y-4 animate-rise-in" noValidate
          onSubmit={(e) => { e.preventDefault(); if (password) save(false); else setError('Enter your current password to turn it off.') }}>
          <Input
            id="twofactor-password"
            label="Current password"
            type="password"
            autoComplete="current-password"
            autoFocus
            placeholder="Confirm it's you"
            value={password}
            onChange={(e) => { setPassword(e.target.value); setError('') }}
            className="!text-base py-3"
          />
          <div className="flex flex-wrap items-center gap-3">
            <Button type="submit" size="md" variant="danger" disabled={busy}>
              {busy ? 'Turning off…' : 'Turn off 2-step'}
            </Button>
            <TextAction onClick={() => { setAsking(false); setPassword(''); setError('') }}>Cancel</TextAction>
          </div>
        </form>
      )}
    </section>
  )
}

function MyAccountTab({ user }) {
  const toast                         = useToast()
  const dispatch                      = useDispatch()
  const { signOut }                   = useAuth()
  const fileInputRef                  = useRef(null)
  const [current, setCurrent]         = useState('')
  const [newPass, setNewPass]         = useState('')
  const [confirm, setConfirm]         = useState('')
  const [showCurrent, setShowCurrent] = useState(false)
  const [showNew, setShowNew]         = useState(false)
  const [saving, setSaving]           = useState(false)
  const [error, setError]             = useState('')
  const [avatarBusy, setAvatarBusy]   = useState(false)
  const [overview, setOverview]       = useState(null)   // null = loading, false = failed

  useEffect(() => {
    let alive = true
    getMyOverview()
      .then(({ data }) => { if (alive) setOverview(data) })
      .catch(() => { if (alive) setOverview(false) })
    return () => { alive = false }
  }, [])

  const metCount      = PASSWORD_REQUIREMENTS.filter((r) => r.test(newPass)).length
  const complexityMet = isPasswordComplex(newPass)
  const strength      = [...STRENGTH].reverse().find((s) => metCount >= s.min)
  const matches       = confirm.length > 0 && confirm === newPass

  const handlePicture = async (e) => {
    const file = e.target.files?.[0]
    e.target.value = ''   // picking the same file again should still trigger a change
    if (!file) return
    if (!file.type.startsWith('image/')) { toast.show('Please choose a picture (JPEG or PNG).', 'error'); return }
    setAvatarBusy(true)
    try {
      const square = await toSquareJpeg(file)
      const { data } = await uploadAvatar(square)
      dispatch(updateAuthUser({ avatarUrl: data.avatarUrl }))
      toast.show('Profile picture updated.', 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || err.message || 'Could not update the profile picture.', 'error')
    } finally {
      setAvatarBusy(false)
    }
  }

  const handleRemovePicture = async () => {
    setAvatarBusy(true)
    try {
      await removeAvatar()
      dispatch(updateAuthUser({ avatarUrl: null }))
      toast.show('Profile picture removed.', 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Could not remove the profile picture.', 'error')
    } finally {
      setAvatarBusy(false)
    }
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    if (!complexityMet) { setError('The new password does not meet all the requirements yet.'); return }
    if (newPass !== confirm) { setError('The new passwords do not match.'); return }
    setSaving(true)
    try {
      await changePassword({ currentPassword: current, newPassword: newPass })
      // The change ends every session (token version bump), this one included - sign out
      // cleanly now instead of letting the next request fail.
      await signOut({ reason: 'password-changed' })
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to update password.')
      setSaving(false)
    }
  }

  const displayName = user?.fullName || user?.username || 'User'
  const isAdmin     = user?.role === 'ADMIN'
  const officeName  = overview?.officeName || user?.officeName

  return (
    <div className="max-w-5xl mx-auto space-y-5">
      {/* ── Identity ─────────────────────────────────────────────────────── */}
      <section className={`${CARD} animate-rise-in`}>
        <div className="p-5 sm:p-6 flex flex-col md:flex-row md:items-center gap-5">
          <div className="flex items-center gap-5 min-w-0">
            <div className="relative flex-shrink-0">
              <UserAvatar user={user} className={`w-24 h-24 text-3xl ring-4 ring-white dark:ring-zinc-900 shadow-sm transition-opacity duration-200 ${avatarBusy ? 'opacity-50' : ''}`} />
              <button type="button" onClick={() => fileInputRef.current?.click()} disabled={avatarBusy}
                aria-label={user?.avatarUrl ? 'Change profile picture' : 'Add profile picture'}
                title={user?.avatarUrl ? 'Change profile picture' : 'Add profile picture'}
                className="absolute -bottom-0.5 -right-0.5 w-9 h-9 rounded-full bg-brand-700 text-white ring-4 ring-white dark:ring-zinc-900 flex items-center justify-center hover:bg-brand-800 hover:scale-105 active:scale-95 focus:outline-none focus-visible:ring-brand-400 transition-all duration-150 disabled:opacity-60">
                {avatarBusy ? (
                  <svg className="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                  </svg>
                ) : (
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                    <path fillRule="evenodd" d="M4 5a2 2 0 00-2 2v8a2 2 0 002 2h12a2 2 0 002-2V7a2 2 0 00-2-2h-1.586a1 1 0 01-.707-.293l-1.121-1.121A2 2 0 0011.172 3H8.828a2 2 0 00-1.414.586L6.293 4.707A1 1 0 015.586 5H4zm6 9a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
                  </svg>
                )}
              </button>
              <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp"
                onChange={handlePicture} className="hidden" aria-label="Choose a profile picture" />
            </div>

            <div className="min-w-0">
              <h2 className="text-2xl font-bold text-gov-700 dark:text-white tracking-tight truncate">{displayName}</h2>
              <p className="text-sm font-mono text-slate-500 dark:text-zinc-400 mt-0.5">@{user?.username}</p>
              <div className="flex flex-wrap items-center gap-2 mt-2.5">
                <Badge label={roleLabel(user?.role)} color={isAdmin ? 'green' : 'blue'} />
                {officeName && (
                  <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium bg-slate-100 dark:bg-zinc-800 text-slate-700 dark:text-zinc-300 ring-1 ring-slate-200 dark:ring-zinc-700">
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                      <path fillRule="evenodd" d="M4 4a2 2 0 012-2h8a2 2 0 012 2v12a1 1 0 110 2h-3a1 1 0 01-1-1v-2a1 1 0 00-1-1H9a1 1 0 00-1 1v2a1 1 0 01-1 1H4a1 1 0 110-2V4zm3 1h2v2H7V5zm2 4H7v2h2V9zm2-4h2v2h-2V5zm2 4h-2v2h2V9z" clipRule="evenodd" />
                    </svg>
                    {officeName}
                  </span>
                )}
              </div>
              <div className="flex flex-wrap items-center gap-x-4 gap-y-1 mt-3">
                <button type="button" onClick={() => fileInputRef.current?.click()} disabled={avatarBusy}
                  className="py-1.5 -my-1.5 text-sm font-medium text-brand-700 dark:text-brand-400 hover:underline underline-offset-2 disabled:opacity-50 disabled:no-underline">
                  {avatarBusy ? 'Saving…' : user?.avatarUrl ? 'Change profile picture' : 'Add profile picture'}
                </button>
                {user?.avatarUrl && !avatarBusy && (
                  <button type="button" onClick={handleRemovePicture}
                    className="py-1.5 -my-1.5 text-sm font-medium text-slate-500 dark:text-zinc-400 hover:text-red-600 dark:hover:text-red-400 hover:underline underline-offset-2">
                    Remove picture
                  </button>
                )}
              </div>
            </div>
          </div>

          {/* Quick facts */}
          <dl className="md:ml-auto grid grid-cols-2 md:grid-cols-1 xl:grid-cols-2 gap-3 md:min-w-[15rem] xl:min-w-[22rem]">
            <div className="rounded-lg bg-slate-50 dark:bg-zinc-800/60 border border-slate-200 dark:border-zinc-700/60 px-4 py-3">
              <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">Member since</dt>
              <dd className="mt-1 text-sm font-semibold text-slate-800 dark:text-zinc-100">
                {overview === null ? <span className="inline-block h-4 w-28 rounded bg-slate-200 dark:bg-zinc-700 animate-pulse" /> : fmtDate(overview?.memberSince)}
              </dd>
            </div>
            <div className="rounded-lg bg-slate-50 dark:bg-zinc-800/60 border border-slate-200 dark:border-zinc-700/60 px-4 py-3">
              <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">2-step verification</dt>
              <dd className="mt-1 text-sm font-semibold">
                {overview === null ? <span className="inline-block h-4 w-12 rounded bg-slate-200 dark:bg-zinc-700 animate-pulse" />
                  : overview?.twoFactorEnabled
                    ? <span className="inline-flex items-center gap-1.5 text-emerald-700 dark:text-emerald-400"><span className="w-2 h-2 rounded-full bg-emerald-500" />On</span>
                    : <span className="inline-flex items-center gap-1.5 text-slate-600 dark:text-zinc-300"><span className="w-2 h-2 rounded-full bg-slate-400" />Off</span>}
              </dd>
            </div>
          </dl>
        </div>
      </section>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5 items-start">
        <div className="lg:col-span-2 space-y-5">
        {/* ── Account details ──────────────────────────────────────────── */}
        <AccountDetailsCard user={user} overview={overview || (overview === null ? null : {})}
          onSaved={(email) => setOverview((o) => ({ ...(o || {}), email }))} />

        {/* ── Change password ──────────────────────────────────────────── */}
        <section className={`${CARD} p-5 sm:p-6 animate-rise-in [animation-delay:110ms]`}>
          <CardHeader icon="password" title="Change password"
            description="Use a password you don't use anywhere else. Afterwards you'll be signed out on every device and asked to sign in with the new one." />

          <FormError>{error}</FormError>

          <form onSubmit={handleSubmit} noValidate className="space-y-5">
            <Input
              id="current-password"
              label="Current password"
              type={showCurrent ? 'text' : 'password'}
              autoComplete="current-password"
              placeholder="Enter your current password"
              value={current}
              onChange={(e) => { setCurrent(e.target.value); setError('') }}
              className="!text-base py-3 pr-20"
              adornmentClassName="pr-1.5"
              endAdornment={<ShowHide shown={showCurrent} onToggle={() => setShowCurrent((v) => !v)} controls="current-password" />}
            />

            <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
              <Input
                id="new-password"
                label="New password"
                type={showNew ? 'text' : 'password'}
                autoComplete="new-password"
                placeholder="Enter a new password"
                value={newPass}
                onChange={(e) => { setNewPass(e.target.value); setError('') }}
                className="!text-base py-3 pr-20"
                adornmentClassName="pr-1.5"
                endAdornment={<ShowHide shown={showNew} onToggle={() => setShowNew((v) => !v)} controls="new-password" />}
              />
              <div>
                <Input
                  id="confirm-password"
                  label="Confirm new password"
                  type={showNew ? 'text' : 'password'}
                  autoComplete="new-password"
                  placeholder="Type it again"
                  value={confirm}
                  onChange={(e) => { setConfirm(e.target.value); setError('') }}
                  className="!text-base py-3"
                />
                {confirm && (
                  <p key={String(matches)} role="status"
                    className={`mt-1.5 flex items-center gap-1.5 text-sm font-medium animate-fade-in ${matches ? 'text-emerald-700 dark:text-emerald-400' : 'text-slate-500 dark:text-zinc-400'}`}>
                    <Check met={matches} />
                    {matches ? 'Passwords match' : "Doesn't match yet"}
                  </p>
                )}
              </div>
            </div>

            {/* Requirements - always visible, so the rules are known before typing */}
            <div className="rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-950/40 px-4 py-3.5">
              <div className="flex items-center justify-between gap-3 mb-2.5">
                <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Password requirements</p>
                {newPass && <p className={`text-sm font-semibold ${strength.text}`} aria-live="polite">{strength.label}</p>}
              </div>
              <div className="flex gap-1.5 mb-3" aria-hidden="true">
                {PASSWORD_REQUIREMENTS.map((r, i) => (
                  <span key={r.key}
                    className={`h-1.5 flex-1 rounded-full transition-colors duration-300 ${i < metCount ? strength.bar : 'bg-slate-200 dark:bg-zinc-800'}`}
                    style={{ transitionDelay: `${i * 40}ms` }} />
                ))}
              </div>
              <ul className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1.5">
                {PASSWORD_REQUIREMENTS.map(({ key, label, test }) => {
                  const met = test(newPass)
                  return (
                    <li key={key} className={`flex items-center gap-2 text-sm transition-colors duration-200 ${met ? 'text-emerald-700 dark:text-emerald-400' : 'text-slate-600 dark:text-zinc-400'}`}>
                      <Check met={met} />
                      {label}
                    </li>
                  )
                })}
              </ul>
            </div>

            <div className="flex flex-wrap items-center gap-3 pt-1">
              <Button type="submit" size="md" disabled={saving || !current || !newPass || !confirm}>
                {saving ? 'Saving…' : 'Update password'}
              </Button>
              {(current || newPass || confirm) && !saving && (
                <TextAction onClick={() => { setCurrent(''); setNewPass(''); setConfirm(''); setError('') }}>Clear</TextAction>
              )}
            </div>
          </form>
        </section>
        </div>

        <div className="space-y-5">
          <TwoStepCard overview={overview || null}
            onChange={(enabled) => setOverview((o) => ({ ...o, twoFactorEnabled: enabled }))} />

          {/* ── Recent activity ─────────────────────────────────────────── */}
          <section className={`${CARD} p-5 sm:p-6 animate-rise-in [animation-delay:200ms]`}>
            <CardHeader icon="activity" title="Your recent activity" description="Your latest actions in the system." />
            {overview === null ? (
              <div className="space-y-3">
                {[0, 1, 2].map((i) => <div key={i} className="h-9 rounded bg-slate-100 dark:bg-zinc-800 animate-pulse" />)}
              </div>
            ) : overview === false ? (
              <p className="text-sm text-slate-500 dark:text-zinc-400">Couldn't load your recent activity.</p>
            ) : overview.recentActivity?.length ? (
              <ol className="relative border-l-2 border-slate-100 dark:border-zinc-800 ml-1.5 space-y-4">
                {overview.recentActivity.map((a, i) => (
                  <li key={i} className="pl-4 relative animate-rise-in" style={{ animationDelay: `${260 + i * 50}ms` }}>
                    <span className="absolute -left-[0.4375rem] top-1.5 w-3 h-3 rounded-full bg-white dark:bg-zinc-900 border-2 border-brand-500" aria-hidden="true" />
                    <p className="text-sm font-medium text-slate-800 dark:text-zinc-100">{actionLabel(a.action)}</p>
                    {a.details && <p className="text-xs text-slate-500 dark:text-zinc-400 truncate" title={a.details}>{a.details}</p>}
                    <p className="text-xs text-slate-400 dark:text-zinc-500 mt-0.5">
                      <time dateTime={a.loggedAt} title={serverTime(a.loggedAt).toLocaleString('en-PH', { timeZone: 'Asia/Manila' })}>{timeAgo(a.loggedAt)}</time>
                    </p>
                  </li>
                ))}
              </ol>
            ) : (
              <p className="text-sm text-slate-500 dark:text-zinc-400">No activity recorded yet.</p>
            )}
          </section>
        </div>
      </div>
    </div>
  )
}

export default MyAccountTab
