import { useState } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import { newIdempotencyKey } from '../../utils/idempotency'
import { useFormDraft } from '../../hooks/useFormDraft'
import DraftNotice from '../../components/common/DraftNotice'
import DatePicker from '../../components/common/DatePicker'
import Select from '../../components/common/Select'

const INPUT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

const MAINT_TYPES  = ['PREVENTIVE', 'CORRECTIVE', 'REPAIR']
const MAINT_STATUS = ['COMPLETED', 'ONGOING', 'SCHEDULED']

function SelectInput({ children, ...props }) {
  return <Select className={INPUT_CLASS} {...props}>{children}</Select>
}

const EMPTY = { assetId: '', maintenanceType: 'PREVENTIVE', findings: '', actionsTaken: '', assignedTo: '', maintenanceDate: '', cost: '', status: 'SCHEDULED', parts: [], labor: [] }

// Parts and labor lines, as on the GSO's Repair and Maintenance Card. A part's total is quantity x
// unit cost; the record's cost (the card's "Cost of Repair") is the sum of all lines, when it has any.
const NEW_PART  = { particular: '', unit: '', quantity: '1', unitCost: '' }
const NEW_LABOR = { particular: '', totalCost: '' }
const num = (v) => (v === '' || v == null || Number.isNaN(Number(v)) ? 0 : Number(v))
const partTotal = (p) => Math.round(num(p.quantity) * num(p.unitCost) * 100) / 100
const peso = (v) => '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const str = (v) => (v == null ? '' : String(v))
const linesOf = (items = []) => ({
  parts: items.filter((i) => i.kind !== 'LABOR').map((i) => ({ particular: i.particular || '', unit: i.unit || '', quantity: str(i.quantity), unitCost: str(i.unitCost) })),
  labor: items.filter((i) => i.kind === 'LABOR').map((i) => ({ particular: i.particular || '', totalCost: str(i.totalCost) })),
})

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
          ...linesOf(initial.items),
        }
      : { ...EMPTY }
  )
  const draft = useFormDraft(`maintenance:${initial?.id ?? 'new'}`, form, setForm, {
    title: isEditing ? `${initial.asset?.propertyNumber || ''}: ${initial.asset?.description || 'Maintenance record'}` : 'Maintenance record',
  })
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)
  const [idempotencyKey] = useState(() => newIdempotencyKey())

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const parts = form.parts || []
  const labor = form.labor || []
  const hasLines = parts.length > 0 || labor.length > 0
  const linesTotal = parts.reduce((t, p) => t + partTotal(p), 0) + labor.reduce((t, l) => t + num(l.totalCost), 0)

  const setLine = (list, i, key) => (e) => {
    const value = e.target.value
    setForm((p) => ({ ...p, [list]: p[list].map((row, j) => (j === i ? { ...row, [key]: value } : row)) }))
    setErrors((p) => { const n = { ...p }; delete n.lines; delete n.cost; return n })
  }
  const addLine = (list) => setForm((p) => ({ ...p, [list]: [...(p[list] || []), list === 'parts' ? { ...NEW_PART } : { ...NEW_LABOR }] }))
  const removeLine = (list, i) => setForm((p) => ({ ...p, [list]: p[list].filter((_, j) => j !== i) }))

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = {}
    if (!form.assetId) errs.assetId = 'Asset is required.'
    if (!form.findings.trim()) errs.findings = 'Findings are required.'
    if (!form.actionsTaken.trim()) errs.actionsTaken = 'Actions taken are required.'
    if (!form.maintenanceDate) errs.maintenanceDate = 'Date is required.'
    if (!hasLines && !form.cost && form.cost !== 0) errs.cost = 'Enter the cost, or add the parts and labor below.'
    const badPart = parts.findIndex((p) => !p.particular.trim() || num(p.quantity) <= 0 || p.unitCost === '')
    const badLabor = labor.findIndex((l) => !l.particular.trim() || l.totalCost === '')
    if (badPart >= 0) errs.lines = `Part ${badPart + 1}: enter the particular, a quantity and the unit cost.`
    else if (badLabor >= 0) errs.lines = `Labor ${badLabor + 1}: enter the particular and the cost.`
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
        cost: hasLines ? linesTotal : Number(form.cost),
        status: form.status,
        items: [
          ...parts.map((p) => ({ kind: 'PART', particular: p.particular.trim(), unit: p.unit.trim() || null, quantity: num(p.quantity), unitCost: num(p.unitCost) })),
          ...labor.map((l) => ({ kind: 'LABOR', particular: l.particular.trim(), totalCost: num(l.totalCost) })),
        ],
      }
      await onSave(payload, idempotencyKey)
      draft.clear()
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
      size="xl"
    >
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        <DraftNotice draft={draft} />
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Asset<span className="text-red-400 ml-0.5">*</span></label>
          <SelectInput value={form.assetId} onChange={set('assetId')}>
            <option value="">Select asset</option>
            {assets.map((a) => (
              <option key={a.id} value={String(a.id)}>{a.propertyNumber}: {a.description}</option>
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
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Particular (work done)<span className="text-red-400 ml-0.5">*</span></label>
          <textarea className={INPUT_CLASS + ' resize-none'} rows={2} placeholder="e.g. Replacement of Various Parts (Automatic Motors)" value={form.actionsTaken} onChange={set('actionsTaken')} />
          {errors.actionsTaken && <p className="text-xs text-red-400">{errors.actionsTaken}</p>}
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Accountable Person</label>
            <input className={INPUT_CLASS} placeholder="Full name of accountable person" value={form.assignedTo} onChange={set('assignedTo')} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Maintenance Date<span className="text-red-400 ml-0.5">*</span></label>
            <DatePicker required className={INPUT_CLASS} value={form.maintenanceDate} onChange={set('maintenanceDate')} />
            {errors.maintenanceDate && <p className="text-xs text-red-400">{errors.maintenanceDate}</p>}
          </div>
        </div>

        {/* Parts and labor, as on the Repair and Maintenance Card */}
        <fieldset className="rounded-lg border border-slate-200 dark:border-zinc-800 p-4 space-y-4">
          <legend className="px-1 text-sm font-semibold text-slate-700 dark:text-zinc-300">Parts and labor</legend>
          <p className="text-xs text-slate-500 dark:text-zinc-400 -mt-2">
            List what was bought and the labor charged. The cost of repair is their total. Leave both empty to type the cost yourself.
          </p>

          <div className="space-y-2">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">Parts</p>
            {parts.length > 0 && (
              <div className="hidden sm:grid grid-cols-12 gap-2 text-xs font-medium text-slate-500 dark:text-zinc-400">
                <span className="col-span-5">Particular</span><span className="col-span-2">Unit</span><span className="col-span-1">Qty</span>
                <span className="col-span-2">Unit cost</span><span className="col-span-2 text-right pr-9">Total</span>
              </div>
            )}
            {parts.map((p, i) => (
              <div key={i} className="grid grid-cols-12 gap-2 items-center">
                <input aria-label={`Part ${i + 1} particular`} className={`${INPUT_CLASS} col-span-12 sm:col-span-5`} placeholder="e.g. Oil Filter" value={p.particular} onChange={setLine('parts', i, 'particular')} maxLength={255} />
                <input aria-label={`Part ${i + 1} unit`} className={`${INPUT_CLASS} col-span-4 sm:col-span-2`} placeholder="pc" value={p.unit} onChange={setLine('parts', i, 'unit')} maxLength={30} />
                <input aria-label={`Part ${i + 1} quantity`} type="number" min="0" step="any" className={`${INPUT_CLASS} col-span-3 sm:col-span-1 px-2`} value={p.quantity} onChange={setLine('parts', i, 'quantity')} />
                <input aria-label={`Part ${i + 1} unit cost`} type="number" min="0" step="0.01" className={`${INPUT_CLASS} col-span-5 sm:col-span-2`} placeholder="0.00" value={p.unitCost} onChange={setLine('parts', i, 'unitCost')} />
                <div className="col-span-12 sm:col-span-2 flex items-center justify-end gap-1">
                  <span className="text-sm tabular-nums text-slate-700 dark:text-zinc-200">{peso(partTotal(p))}</span>
                  <button type="button" onClick={() => removeLine('parts', i)} aria-label={`Remove part ${i + 1}`} className="p-1.5 rounded-md text-slate-400 hover:text-red-500 hover:bg-red-500/10">
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
                  </button>
                </div>
              </div>
            ))}
            <Button type="button" variant="secondary" size="sm" onClick={() => addLine('parts')}>Add part</Button>
          </div>

          <div className="space-y-2">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">Labor</p>
            {labor.map((l, i) => (
              <div key={i} className="grid grid-cols-12 gap-2 items-center">
                <input aria-label={`Labor ${i + 1} particular`} className={`${INPUT_CLASS} col-span-12 sm:col-span-8`} placeholder="e.g. Change Oil Labor" value={l.particular} onChange={setLine('labor', i, 'particular')} maxLength={255} />
                <input aria-label={`Labor ${i + 1} cost`} type="number" min="0" step="0.01" className={`${INPUT_CLASS} col-span-10 sm:col-span-3`} placeholder="0.00" value={l.totalCost} onChange={setLine('labor', i, 'totalCost')} />
                <div className="col-span-2 sm:col-span-1 flex justify-end">
                  <button type="button" onClick={() => removeLine('labor', i)} aria-label={`Remove labor ${i + 1}`} className="p-1.5 rounded-md text-slate-400 hover:text-red-500 hover:bg-red-500/10">
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
                  </button>
                </div>
              </div>
            ))}
            <Button type="button" variant="secondary" size="sm" onClick={() => addLine('labor')}>Add labor</Button>
          </div>
          {errors.lines && <p className="text-xs text-red-400">{errors.lines}</p>}
        </fieldset>

        <div className="flex flex-col gap-1.5">
          <label htmlFor="maint-cost" className="text-sm font-medium text-slate-700 dark:text-zinc-300">Cost of Repair (PHP){!hasLines && <span className="text-red-400 ml-0.5">*</span>}</label>
          {hasLines ? (
            <input id="maint-cost" readOnly value={peso(linesTotal)} className={`${INPUT_CLASS} bg-slate-50 dark:bg-zinc-900 font-semibold tabular-nums cursor-default`} aria-describedby="maint-cost-hint" />
          ) : (
            <input id="maint-cost" type="number" min="0" step="0.01" className={INPUT_CLASS} placeholder="0.00" value={form.cost} onChange={set('cost')} aria-describedby="maint-cost-hint" />
          )}
          <p id="maint-cost-hint" className="text-xs text-slate-500 dark:text-zinc-400">{hasLines ? 'The total of the parts and labor above.' : 'No parts or labor listed, so type the total cost.'}</p>
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
