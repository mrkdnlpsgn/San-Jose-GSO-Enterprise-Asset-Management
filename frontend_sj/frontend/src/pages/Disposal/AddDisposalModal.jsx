import { useState } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import { newIdempotencyKey } from '../../utils/idempotency'

const METHODS   = ['SALE', 'TRANSFER', 'DESTRUCTION', 'OTHERS']
const STATUSES  = ['PENDING', 'APPROVED', 'COMPLETED']
const DISPOSABLE_CONDITIONS = ['REPAIRABLE', 'UNSERVICEABLE']

function fmtMoney(n) {
  if (n == null) return '—'
  return `₱${Number(n).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}
const INPUT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

export default function AddDisposalModal({ onClose, onSave, initial = null, assets = [], users = [] }) {
  const isEditing = !!initial

  const [form, setForm] = useState({
    assetId:            initial?.asset?.id           ? String(initial.asset.id) : '',
    reason:             initial?.reason              || '',
    inspectionFindings: initial?.inspectionFindings  || '',
    recommendedMethod:  initial?.recommendedMethod   || 'SALE',
    disposalStatus:     initial?.disposalStatus      || 'PENDING',
    inspectionDate:     initial?.inspectionDate      || '',
    approvedBy:         initial?.approvedBy           || '',
    appraisedValue:     initial?.appraisedValue != null ? String(initial.appraisedValue) : '',
    orNumber:           initial?.orNumber             || '',
    amount:             initial?.amount != null      ? String(initial.amount) : '',
  })
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)
  const [idempotencyKey] = useState(() => newIdempotencyKey())

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  // Disposal is gated on physical condition, not book value — a SERVICEABLE
  // asset shouldn't even be selectable here. The currently-selected asset (when
  // editing) is always kept so its condition can still be displayed.
  const selectableAssets = assets.filter((a) =>
    DISPOSABLE_CONDITIONS.includes(a.condition) || String(a.id) === form.assetId)

  const selectedAsset = assets.find((a) => String(a.id) === form.assetId)

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = {}
    if (!form.assetId)            errs.assetId           = 'Asset is required.'
    if (!form.reason.trim())      errs.reason            = 'Reason is required.'
    if (!form.inspectionFindings.trim()) errs.inspectionFindings = 'Inspection findings are required.'
    if (!form.inspectionDate)     errs.inspectionDate    = 'Inspection date is required.'
    if (Object.keys(errs).length) { setErrors(errs); return }

    setSaving(true)
    try {
      const payload = {
        assetId:            Number(form.assetId),
        reason:             form.reason.trim(),
        inspectionFindings: form.inspectionFindings.trim(),
        recommendedMethod:  form.recommendedMethod,
        disposalStatus:     form.disposalStatus,
        inspectionDate:     form.inspectionDate,
        approvedBy:         form.approvedBy.trim() || null,
        appraisedValue:     form.appraisedValue !== '' ? Number(form.appraisedValue) : null,
        orNumber:           form.orNumber.trim() || null,
        amount:             form.amount !== ''         ? Number(form.amount) : null,
      }
      await onSave(payload, idempotencyKey)
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save disposal record.' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title={isEditing ? 'Edit Disposal Record' : 'Add Disposal Record'} size="lg" onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Asset<span className="text-red-400 ml-0.5">*</span></label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.assetId} onChange={set('assetId')} disabled={isEditing}>
              <option value="">— Select asset —</option>
              {selectableAssets.map((a) => <option key={a.id} value={String(a.id)}>{a.propertyNumber} — {a.description} ({a.condition})</option>)}
            </select>
            <Chevron />
          </div>
          {errors.assetId && <p className="text-xs text-red-400">{errors.assetId}</p>}
          <p className="text-xs text-slate-400 dark:text-zinc-500">Only assets marked REPAIRABLE or UNSERVICEABLE can be disposed.</p>
          {selectedAsset && (
            <div className="mt-1 grid grid-cols-2 gap-x-4 gap-y-1 text-xs rounded-lg border border-slate-200 dark:border-zinc-700 bg-slate-50 dark:bg-zinc-800/50 px-3 py-2.5">
              <span className="text-slate-400 dark:text-zinc-500">Unit Cost</span>
              <span className="text-right font-medium text-slate-700 dark:text-zinc-300">{fmtMoney(selectedAsset.unitValue)}</span>
              <span className="text-slate-400 dark:text-zinc-500">Accumulated Depreciation</span>
              <span className="text-right font-medium text-slate-700 dark:text-zinc-300">{fmtMoney(selectedAsset.accumulatedDepreciation)}</span>
              <span className="text-slate-400 dark:text-zinc-500">Carrying Amount</span>
              <span className="text-right font-medium text-slate-700 dark:text-zinc-300">{fmtMoney(selectedAsset.carryingAmount)}</span>
            </div>
          )}
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Reason for Disposal<span className="text-red-400 ml-0.5">*</span></label>
          <textarea className={INPUT_CLASS + ' resize-none'} rows={3} placeholder="Explain why this asset should be disposed…" value={form.reason} onChange={set('reason')} />
          {errors.reason && <p className="text-xs text-red-400">{errors.reason}</p>}
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Inspection Findings<span className="text-red-400 ml-0.5">*</span></label>
          <textarea className={INPUT_CLASS + ' resize-none'} rows={3} placeholder="Describe the inspection findings…" value={form.inspectionFindings} onChange={set('inspectionFindings')} />
          {errors.inspectionFindings && <p className="text-xs text-red-400">{errors.inspectionFindings}</p>}
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Recommended Method<span className="text-red-400 ml-0.5">*</span></label>
            <div className="relative">
              <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.recommendedMethod} onChange={set('recommendedMethod')}>
                {METHODS.map((m) => <option key={m} value={m}>{m}</option>)}
              </select>
              <Chevron />
            </div>
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Disposal Status</label>
            <div className="relative">
              <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.disposalStatus} onChange={set('disposalStatus')}>
                {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
              <Chevron />
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Inspection Date<span className="text-red-400 ml-0.5">*</span></label>
            <input type="date" className={INPUT_CLASS} value={form.inspectionDate} onChange={set('inspectionDate')} />
            {errors.inspectionDate && <p className="text-xs text-red-400">{errors.inspectionDate}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Approved By <span className="text-slate-400 font-normal">(optional)</span></label>
            <input className={INPUT_CLASS} placeholder="Full name of approving authority" value={form.approvedBy} onChange={set('approvedBy')} />
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Appraised Value <span className="text-slate-400 font-normal">(optional)</span></label>
            <input type="number" step="0.01" min="0" className={INPUT_CLASS} placeholder="0.00" value={form.appraisedValue} onChange={set('appraisedValue')} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">OR No. <span className="text-slate-400 font-normal">(optional)</span></label>
            <input className={INPUT_CLASS} placeholder="Official Receipt number" value={form.orNumber} onChange={set('orNumber')} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Amount <span className="text-slate-400 font-normal">(optional)</span></label>
            <input type="number" step="0.01" min="0" className={INPUT_CLASS} placeholder="0.00" value={form.amount} onChange={set('amount')} />
          </div>
        </div>
        <p className="text-xs text-slate-400 dark:text-zinc-500 -mt-2">
          OR No. and Amount are typically filled in once the item has actually been sold.
        </p>

        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : isEditing ? 'Save Changes' : 'Add Disposal Record'}</Button>
        </div>
      </form>
    </Modal>
  )
}

function Chevron() {
  return (
    <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
      </svg>
    </div>
  )
}
