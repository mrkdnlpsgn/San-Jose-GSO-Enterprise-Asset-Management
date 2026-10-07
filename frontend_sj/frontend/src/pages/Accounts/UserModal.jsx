import { useState, useEffect } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import { newIdempotencyKey } from '../../utils/idempotency'
import { PASSWORD_REQUIREMENTS, isPasswordComplex } from '../../utils/passwordPolicy'

const ROLES = [
  { value: 'ADMIN', label: 'Administrator' },
  { value: 'STAFF', label: 'GSO Staff' },
]

// Markers that LastPass, 1Password and Bitwarden respect to skip a field.
const NO_EXTENSION_AUTOFILL = { 'data-lpignore': 'true', 'data-1p-ignore': 'true', 'data-bwignore': 'true' }

const EMPTY = { username: '', email: '', fullName: '', password: '', confirmPassword: '', generatePassword: false, role: 'STAFF', isActive: true, twoFactorEnabled: true }

function Field({ label, required, error, children }) {
  return (
    <div className="flex flex-col gap-1.5">
      <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">
        {label}{required && <span className="text-red-400 ml-0.5">*</span>}
      </label>
      {children}
      {error && <p className="text-xs text-red-400">{error}</p>}
    </div>
  )
}

function TextInput({ error, ...props }) {
  return (
    <input
      className={`w-full rounded-md border px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600
        focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150
        ${error ? 'border-red-500' : 'border-slate-200 dark:border-zinc-700 hover:border-slate-300 dark:hover:border-zinc-600'}`}
      {...props}
    />
  )
}

function SelectInput({ children, ...props }) {
  return (
    <div className="relative">
      <select
        className="w-full appearance-none rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 pr-9 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white
          hover:border-slate-300 dark:hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150"
        {...props}
      >
        {children}
      </select>
      <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-500">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
        </svg>
      </div>
    </div>
  )
}

function UserModal({ onClose, onSave, initial = null }) {
  const isEditing = initial !== null
  const [form, setForm] = useState(
    isEditing
      ? {
          username: initial.username || '',
          email: initial.email || '',
          fullName: initial.fullName || '',
          password: '',
          confirmPassword: '',
          role: initial.role || 'STAFF',
          isActive: initial.isActive !== undefined ? initial.isActive : true,
          twoFactorEnabled: Boolean(initial.twoFactorEnabled),
        }
      : EMPTY
  )
  const [errors, setErrors]   = useState({})
  const [saving, setSaving]   = useState(false)
  const [idempotencyKey] = useState(() => newIdempotencyKey())

  const set = (key) => (e) => {
    const value = e.target.type === 'checkbox' ? e.target.checked : e.target.value
    setForm((p) => ({ ...p, [key]: value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const emailValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())

  useEffect(() => {
    if (form.generatePassword && !emailValid) {
      setForm((p) => ({ ...p, generatePassword: false }))
    }
  }, [form.generatePassword, emailValid])

  // The sign-in code is emailed, so 2-step verification can't stay on without an email.
  useEffect(() => {
    if (form.twoFactorEnabled && !emailValid) {
      setForm((p) => ({ ...p, twoFactorEnabled: false }))
    }
  }, [form.twoFactorEnabled, emailValid])

  const validate = () => {
    const errs = {}
    if (!form.username.trim()) errs.username = 'Username is required.'
    if (form.email.trim() && !emailValid)
      errs.email = 'Enter a valid email address.'
    if (!form.fullName.trim()) errs.fullName = 'Full name is required.'
    if (!isEditing && form.generatePassword) {
      if (!form.email.trim() || !emailValid) errs.email = 'A valid email is required to auto-generate and send a password.'
    } else {
      if (!isEditing && !form.password.trim()) {
        errs.password = 'Password is required.'
      } else if (form.password && !isPasswordComplex(form.password)) {
        errs.password = 'Password does not meet the requirements below.'
      }
      if (form.password && form.password !== form.confirmPassword) {
        errs.confirmPassword = 'Passwords do not match.'
      }
    }
    if (!form.role) errs.role = 'Role is required.'
    return errs
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = validate()
    if (Object.keys(errs).length) { setErrors(errs); return }
    setSaving(true)
    try {
      const payload = { ...form }
      delete payload.confirmPassword
      if (!isEditing && payload.generatePassword) delete payload.password
      if (isEditing && !payload.password) delete payload.password
      await onSave(payload, idempotencyKey)
      onClose()
    } catch (err) {
      const msg = err.response?.data?.message || 'Failed to save account.'
      setErrors({ _global: msg })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal
      title={isEditing ? 'Edit Account' : 'Create Account'}
      subtitle={isEditing ? `Editing ${initial.fullName || initial.username}` : 'Add a new staff or admin account'}
      onClose={onClose}
    >
      {/* The admin types someone else's details here, so browser autofill (and password-manager
          extensions) must stay out: they'd offer the admin's own name/email — and Chrome's
          name/address autofill popup was crashing the whole browser on the Full Name field. */}
      <form onSubmit={handleSubmit} noValidate autoComplete="off" className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">
            {errors._global}
          </div>
        )}

        <Field label="Username" required error={errors.username}>
          <TextInput
            placeholder="e.g. jdelacruz"
            {...NO_EXTENSION_AUTOFILL}
            value={form.username}
            onChange={set('username')}
            error={errors.username}
            autoComplete="off"
          />
        </Field>

        <Field label="Email" error={errors.email}>
          <TextInput
            type="email"
            autoComplete="off"
            {...NO_EXTENSION_AUTOFILL}
            placeholder="e.g. jdelacruz@sanjosebatangas.gov.ph"
            value={form.email}
            onChange={set('email')}
            error={errors.email}
          />
          <p className="text-xs text-slate-400 dark:text-zinc-500 mt-1">
            Needed for this user to use "Forgot password" — leave blank if unavailable.
          </p>
        </Field>

        <Field label="Full Name" required error={errors.fullName}>
          <TextInput
            placeholder="e.g. Juan Dela Cruz"
            autoComplete="off"
            {...NO_EXTENSION_AUTOFILL}
            value={form.fullName}
            onChange={set('fullName')}
            error={errors.fullName}
          />
        </Field>

        {!isEditing && (
          <label className={`flex items-start gap-2.5 select-none ${emailValid ? 'cursor-pointer' : 'cursor-not-allowed opacity-60'}`}>
            <input
              type="checkbox"
              className="mt-0.5"
              checked={form.generatePassword}
              disabled={!emailValid}
              onChange={set('generatePassword')}
            />
            <span className="text-sm text-slate-600 dark:text-zinc-300">
              Auto-generate a password and email it to the address above
              {!emailValid && <span className="block text-xs text-slate-400 dark:text-zinc-500 mt-0.5">Enter a valid email to enable this.</span>}
            </span>
          </label>
        )}

        {form.generatePassword ? (
          <p className="text-xs text-slate-400 dark:text-zinc-500 bg-slate-50 dark:bg-zinc-800/60 border border-slate-200 dark:border-zinc-700 rounded-md px-3.5 py-2.5">
            A temporary password will be generated and emailed to <span className="font-medium">{form.email}</span>. The user should change it after logging in.
          </p>
        ) : (
          <>
            <Field label={isEditing ? 'New Password (leave blank to keep)' : 'Password'} required={!isEditing} error={errors.password}>
              <TextInput
                type="password"
                placeholder={isEditing ? 'Leave blank to keep current password' : 'Enter password'}
                value={form.password}
                onChange={set('password')}
                error={errors.password}
                autoComplete="new-password"
              />
              {form.password && (
                <ul className="mt-1 space-y-0.5">
                  {PASSWORD_REQUIREMENTS.map(({ key, label, test }) => {
                    const met = test(form.password)
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
            </Field>

            {form.password && (
              <Field label="Confirm Password" required={!isEditing} error={errors.confirmPassword}>
                <TextInput
                  type="password"
                  placeholder="Re-enter password"
                  value={form.confirmPassword}
                  onChange={set('confirmPassword')}
                  error={errors.confirmPassword}
                  autoComplete="new-password"
                />
              </Field>
            )}
          </>
        )}

        <Field label="Role" required error={errors.role}>
          <SelectInput value={form.role} onChange={set('role')}>
            {ROLES.map(({ value, label }) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </SelectInput>
        </Field>

        <Field label="Status" error={errors.isActive}>
          <label className="flex items-center gap-2.5 cursor-pointer select-none">
            <div className="relative">
              <input
                type="checkbox"
                className="sr-only peer"
                checked={form.isActive}
                onChange={set('isActive')}
              />
              <div className="w-9 h-5 rounded-full transition-colors duration-200 bg-slate-200 dark:bg-zinc-700 peer-checked:bg-brand-500" />
              <div className="absolute top-0.5 left-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform duration-200 peer-checked:translate-x-4" />
            </div>
            <span className="text-sm text-slate-600 dark:text-zinc-300">{form.isActive ? 'Active' : 'Inactive'}</span>
          </label>
        </Field>

        <Field label="2-step verification">
          <label className={`flex items-start gap-2.5 select-none ${emailValid ? 'cursor-pointer' : 'cursor-not-allowed opacity-60'}`}>
            <div className="relative mt-0.5">
              <input
                type="checkbox"
                className="sr-only peer"
                checked={form.twoFactorEnabled}
                disabled={!emailValid}
                onChange={set('twoFactorEnabled')}
              />
              <div className="w-9 h-5 rounded-full transition-colors duration-200 bg-slate-200 dark:bg-zinc-700 peer-checked:bg-brand-500 peer-focus-visible:ring-2 peer-focus-visible:ring-brand-500 peer-focus-visible:ring-offset-2" />
              <div className="absolute top-0.5 left-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform duration-200 peer-checked:translate-x-4" />
            </div>
            <span className="text-sm text-slate-600 dark:text-zinc-300">
              {form.twoFactorEnabled ? 'Required at sign-in' : 'Off'}
              <span className="block text-xs text-slate-400 dark:text-zinc-500 mt-0.5">
                {emailValid
                  ? 'When on, signing in also needs a 6-digit code emailed to the address above.'
                  : 'Needs an email address — the sign-in code is sent there.'}
              </span>
            </span>
          </label>
        </Field>

        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800 mt-2">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>
            {saving ? 'Saving…' : isEditing ? 'Save Changes' : 'Create Account'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}

export default UserModal
