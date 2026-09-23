import { useState } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'

// Deactivating an account (e.g. staff retired or left GSO) — accounts are never deleted, so
// their audit logs and history stay intact. If it still has assets (as accountable person or
// current user) the admin picks which active account takes them over.
function DeactivateAccountModal({ user, accounts, onClose, onConfirm }) {
  const [transferTo, setTransferTo] = useState('')
  const [error, setError]           = useState('')
  const [saving, setSaving]         = useState(false)

  const name       = user.fullName || user.username
  const hasAssets  = user.assetCount > 0
  const candidates = accounts.filter((a) => a.id !== user.id && a.isActive)

  const handleDeactivate = async () => {
    if (hasAssets && !transferTo) { setError('Choose who will take over these assets.'); return }
    setSaving(true)
    try {
      await onConfirm(hasAssets ? Number(transferTo) : null)
      onClose()
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to deactivate account.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title="Deactivate this account?" subtitle={`"${name}" won't be able to sign in. Their history is kept, and you can reactivate the account later.`} onClose={onClose}>
      <div className="space-y-4">
        {error && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{error}</div>
        )}

        {hasAssets ? (
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">
              Transfer {user.assetCount} asset{user.assetCount !== 1 ? 's' : ''} to<span className="text-red-400 ml-0.5">*</span>
            </label>
            <select
              value={transferTo}
              onChange={(e) => { setTransferTo(e.target.value); setError('') }}
              className="w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              <option value="">— Select an account —</option>
              {candidates.map((a) => (
                <option key={a.id} value={String(a.id)}>
                  {a.fullName || a.username} (@{a.username}){a.officeName ? ` — ${a.officeName}` : ''}
                </option>
              ))}
            </select>
            <p className="text-xs text-slate-400 dark:text-zinc-500">
              They become the accountable person (or current user) of every asset {name} holds.
            </p>
          </div>
        ) : (
          <p className="text-sm text-slate-500 dark:text-zinc-400">This account has no assets assigned to it.</p>
        )}

        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="button" variant="danger" size="md" onClick={handleDeactivate} disabled={saving}>
            {saving ? 'Deactivating…' : hasAssets ? 'Transfer & Deactivate' : 'Deactivate Account'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}

export default DeactivateAccountModal
