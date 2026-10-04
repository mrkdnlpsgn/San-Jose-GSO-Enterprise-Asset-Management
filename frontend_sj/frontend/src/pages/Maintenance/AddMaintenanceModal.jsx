import { useState } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import { newIdempotencyKey } from '../../utils/idempotency'

const INPUT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

const MAINT_TYPES  = ['PREVENTIVE', 'CORRECTIVE', 'REPAIR']
const MAINT_STATUS = ['COMPLETED', 'ONGOING', 'SCHEDULED']

function SelectInput({ children, ...props }) {
  return (
    <div className="relative">
      <select className={INPUT_CLASS + ' appearance-none pr-9'} {...props}>{children}</select>
      <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
        </svg>
      </div>
    </div>
  )
}

const EMPTY = { assetId: '', maintenanceType: 'PREVENTIVE', findings: '', actionsTaken: '', assignedTo: '', maintenanceDate: '', cost: '', status: 'SCHEDULED' }

function AddMaintenanceModal({ onClose, onSave, initial = null, assets = [], users = [] }) {
  const isEditing = !!initial
  const [form, setForm]     = useState(
    isEditing
      ? {
          assetId: initial.asset?.id ? String(initial.asset.id) : '',
          maintenanceType: initial.maintenanceType || 'PREVENTIVE',
          findings: initial.findings || '',
          actionsTaken: initial.actionsTaken || '',
          assignedTo: initial.assignedTo || '',
          maintenanceDate: initial.maintenanceDate ? initial.maintenanceDate.slice(0, 10) : '',
          cost: initial.cost !== null && initial.cost !== undefined ? String(initial.cost) : '',
          status: initial.status || 'SCHEDULED',
        }
      : { ...EMPTY }
  )
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)
  const [idempotencyKey] = useState(() => newIdempotencyKey())

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = {}
    if (!form.assetId) errs.assetId = 'Asset is required.'
    if (!form.findings.trim()) errs.findings = 'Findings are required.'
    if (!form.actionsTaken.trim()) errs.actionsTaken = 'Actions taken are required.'
    if (!form.maintenanceDate) errs.maintenanceDate = 'Date is required.'
    if (!form.cost && form.cost !== 0) errs.cost = 'Cost is required.'
    if (Object.keys(errs).length) { setErrors(errs); return }
    setSaving(true)
    try {
      const payload = {
        assetId: Number(form.assetId),
        maintenanceType: form.maintenanceType,
        findings: form.findings.trim(),
        actionsTaken: form.actionsTaken.trim(),
        assignedTo: form.assignedTo.trim() || null,
        maintenanceDate: form.maintenanceDate,
        cost: Number(form.cost),
        status: form.status,
      }
      await onSave(payload, idempotencyKey)
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save.' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal
      title={isEditing ? 'Edit Maintenance Record' : 'Add Maintenance Record'}
      onClose={onClose}
    >
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Asset<span className="text-red-400 ml-0.5">*</span></label>
          <SelectInput value={form.assetId} onChange={set('assetId')}>
            <option value="">— Select asset —</option>
            {assets.map((a) => (
              <option key={a.id} value={String(a.id)}>{a.propertyNumber} — {a.description}</option>
            ))}
          </SelectInput>
          {errors.assetId && <p className="text-xs text-red-400">{errors.assetId}</p>}
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Type<span className="text-red-400 ml-0.5">*</span></label>
            <SelectInput value={form.maintenanceType} onChange={set('maintenanceType')}>
              {MAINT_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </SelectInput>
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Status<span className="text-red-400 ml-0.5">*</span></label>
            <SelectInput value={form.status} onChange={set('status')}>
              {MAINT_STATUS.map((s) => <option key={s} value={s}>{s}</option>)}
            </SelectInput>
          </div>
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Findings<span className="text-red-400 ml-0.5">*</span></label>
          <textarea className={INPUT_CLASS + ' resize-none'} rows={3} placeholder="Describe the findings…" value={form.findings} onChange={set('findings')} />
          {errors.findings && <p className="text-xs text-red-400">{errors.findings}</p>}
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Actions Taken<span className="text-red-400 ml-0.5">*</span></label>
          <textarea className={INPUT_CLASS + ' resize-none'} rows={3} placeholder="Describe the actions taken…" value={form.actionsTaken} onChange={set('actionsTaken')} />
          {errors.actionsTaken && <p className="text-xs text-red-400">{errors.actionsTaken}</p>}
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Accountable Person</label>
            <input className={INPUT_CLASS} placeholder="Full name of accountable person" value={form.assignedTo} onChange={set('assignedTo')} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Maintenance Date<span className="text-red-400 ml-0.5">*</span></label>
            <input type="date" className={INPUT_CLASS} value={form.maintenanceDate} onChange={set('maintenanceDate')} />
            {errors.maintenanceDate && <p className="text-xs text-red-400">{errors.maintenanceDate}</p>}
          </div>
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Cost (PHP)<span className="text-red-400 ml-0.5">*</span></label>
          <input type="number" min="0" step="0.01" className={INPUT_CLASS} placeholder="0.00" value={form.cost} onChange={set('cost')} />
          {errors.cost && <p className="text-xs text-red-400">{errors.cost}</p>}
        </div>

        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : isEditing ? 'Save Changes' : 'Add Record'}</Button>
        </div>
      </form>
    </Modal>
  )
}

export default AddMaintenanceModal
