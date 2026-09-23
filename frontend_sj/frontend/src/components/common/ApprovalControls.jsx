import { useState } from 'react'
import Modal from './Modal'
import Button from './Button'

// Maintenance / disposal records a STAFF account adds are requests: they wait for an
// admin to approve (then staff can edit them) or reject them with a reason.
export const isApproved = (r) => !r.approvalStatus || r.approvalStatus === 'APPROVED'

export function ApprovalBadge({ record }) {
  if (record.approvalStatus === 'PENDING_APPROVAL') {
    return (
      <span className="inline-flex items-center mt-1 px-2 py-0.5 rounded-full text-2xs font-semibold bg-amber-500/10 text-amber-500 ring-1 ring-amber-500/20"
        title={record.requestedByName ? `Requested by ${record.requestedByName}` : undefined}>
        Awaiting admin approval
      </span>
    )
  }
  if (record.approvalStatus === 'REJECTED') {
    return (
      <span className="inline-flex items-center mt-1 px-2 py-0.5 rounded-full text-2xs font-semibold bg-red-500/10 text-red-400 ring-1 ring-red-500/20"
        title={record.reviewNote ? `Reason: ${record.reviewNote}` : undefined}>
        Request rejected
      </span>
    )
  }
  return null
}

// Approve / reject buttons shown to admins on a pending request.
export function ApprovalActions({ record, onApprove, onReject }) {
  if (record.approvalStatus !== 'PENDING_APPROVAL') return null
  return (
    <>
      <button onClick={() => onApprove(record)} title="Approve request"
        className="p-1.5 rounded-md text-emerald-500 hover:bg-emerald-500/10 transition-all duration-150">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" /></svg>
      </button>
      <button onClick={() => onReject(record)} title="Reject request"
        className="p-1.5 rounded-md text-red-400 hover:bg-red-500/10 transition-all duration-150">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
      </button>
    </>
  )
}

export function RejectRequestModal({ record, describe, onClose, onConfirm }) {
  const [note, setNote]     = useState('')
  const [error, setError]   = useState('')
  const [saving, setSaving] = useState(false)

  const submit = async () => {
    if (!note.trim()) { setError('Give a reason so the requester knows what to fix.'); return }
    setSaving(true)
    try {
      await onConfirm(note.trim())
      onClose()
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to reject the request.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title="Reject request?" subtitle={describe(record)} onClose={onClose}>
      <div className="space-y-4">
        {error && <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{error}</div>}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Reason<span className="text-red-400 ml-0.5">*</span></label>
          <textarea rows={3} value={note} onChange={(e) => { setNote(e.target.value); setError('') }} maxLength={255} autoFocus
            placeholder="e.g. Duplicate of an existing record"
            className="w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-brand-500" />
          {record.requestedByName && (
            <p className="text-xs text-slate-400 dark:text-zinc-500">Requested by {record.requestedByName}.</p>
          )}
        </div>
        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="button" variant="danger" size="md" onClick={submit} disabled={saving}>{saving ? 'Rejecting…' : 'Reject Request'}</Button>
        </div>
      </div>
    </Modal>
  )
}
