import { useState, useEffect, useRef } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import { newIdempotencyKey } from '../../utils/idempotency'
import { useFormDraft } from '../../hooks/useFormDraft'
import DraftNotice from '../../components/common/DraftNotice'
import DatePicker from '../../components/common/DatePicker'
import Select from '../../components/common/Select'
import { getMaintenancePhotos, uploadMaintenancePhoto, deleteMaintenancePhoto } from '../../services/maintenanceService'
import { resolveUploadUrl } from '../../services/api'

const INPUT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

const MAINT_TYPES  = ['PREVENTIVE', 'CORRECTIVE', 'REPAIR']
const MAINT_STATUS = ['COMPLETED', 'ONGOING', 'SCHEDULED']

const MAX_SIZE = 10 * 1024 * 1024
const ACCEPTED = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']

function SelectInput({ children, ...props }) {
  return <Select className={INPUT_CLASS} {...props}>{children}</Select>
}

const EMPTY = { assetId: '', maintenanceType: 'PREVENTIVE', findings: '', actionsTaken: '', assignedTo: '', maintenanceDate: '', completedDate: '', cost: '', status: 'SCHEDULED', parts: [], labor: [] }

// Parts and labor lines, as on the GSO's Repair and Maintenance Card. A part's total is quantity x
// unit cost; the record's cost (the card's "Cost of Repair") is the sum of all lines, when it has any.
// Each part carries its photos: a pre-maintenance photo of the damaged part and a post-maintenance
// photo of the part that replaced it. An additional part (found needed during the repair) has only
// the second. `key` tells rows apart before they are saved; `id` is the saved line.
// random, so rows restored from a saved draft never share a key with new ones
const newKey = () => Math.random().toString(36).slice(2, 10)
const NEW_PART  = () => ({ key: newKey(), id: null, particular: '', unit: '', quantity: '1', unitCost: '', additional: false })
const NEW_LABOR = () => ({ key: newKey(), id: null, particular: '', totalCost: '' })
const num = (v) => (v === '' || v == null || Number.isNaN(Number(v)) ? 0 : Number(v))
const partTotal = (p) => Math.round(num(p.quantity) * num(p.unitCost) * 100) / 100
const peso = (v) => '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const str = (v) => (v == null ? '' : String(v))
const todayKey = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' })
const linesOf = (items = []) => ({
  parts: items.filter((i) => i.kind !== 'LABOR').map((i) => ({ key: newKey(), id: i.id ?? null, particular: i.particular || '', unit: i.unit || '', quantity: str(i.quantity), unitCost: str(i.unitCost), additional: !!i.additional })),
  labor: items.filter((i) => i.kind === 'LABOR').map((i) => ({ key: newKey(), id: i.id ?? null, particular: i.particular || '', totalCost: str(i.totalCost) })),
})

const STAGES = [
  { key: 'BEFORE', label: 'Pre-maintenance', hint: 'The damaged part as found' },
  { key: 'AFTER',  label: 'Post-maintenance', hint: 'The new part, installed' },
]

function AddMaintenanceModal({ onClose, onSave, onSaved, initial = null, assets = [], users = [] }) {
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
          completedDate: initial.completedDate ? initial.completedDate.slice(0, 10) : '',
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

  // Saved photos of the record (from the server) and photos picked for parts not saved yet,
  // uploaded once the record is saved: { [partKey]: { BEFORE: [{ file, url }], AFTER: [...] } }.
  const [photos, setPhotos]   = useState([])
  const [pending, setPending] = useState({})
  const [uploading, setUploading] = useState(null) // `${partKey}:${stage}` being uploaded
  const [removing, setRemoving]   = useState(null) // saved photo waiting for the delete confirmation
  const [preview, setPreview]     = useState(null) // url shown full size

  useEffect(() => {
    if (!isEditing) return
    getMaintenancePhotos(initial.id).then(({ data }) => setPhotos(data)).catch(() => {})
  }, [isEditing, initial?.id])

  // the picked photos' preview urls are released when the form closes
  const pendingRef = useRef(pending)
  pendingRef.current = pending
  useEffect(() => () => {
    Object.values(pendingRef.current).forEach((st) => Object.values(st).flat().forEach((p) => URL.revokeObjectURL(p.url)))
  }, [])

  const set = (key) => (e) => {
    const value = e.target.value
    setForm((p) => ({
      ...p,
      [key]: value,
      // finishing a repair needs the day it was finished; today unless changed
      ...(key === 'status' && value === 'COMPLETED' && !p.completedDate ? { completedDate: todayKey() } : {}),
    }))
    setErrors((p) => { const n = { ...p }; delete n[key]; delete n.photos; return n })
  }

  const parts = form.parts || []
  const labor = form.labor || []
  const hasLines = parts.length > 0 || labor.length > 0
  const linesTotal = parts.reduce((t, p) => t + partTotal(p), 0) + labor.reduce((t, l) => t + num(l.totalCost), 0)
  const completing = form.status === 'COMPLETED' && initial?.status !== 'COMPLETED'

  const setLine = (list, i, key) => (e) => {
    const value = e.target.value
    setForm((p) => ({ ...p, [list]: p[list].map((row, j) => (j === i ? { ...row, [key]: value } : row)) }))
    setErrors((p) => { const n = { ...p }; delete n.lines; delete n.cost; return n })
  }
  const addLine = (list, extra = {}) => setForm((p) => ({ ...p, [list]: [...(p[list] || []), list === 'parts' ? { ...NEW_PART(), ...extra } : NEW_LABOR()] }))
  const removeLine = (list, i) => {
    const row = form[list][i]
    if (pending[row.key]) {
      Object.values(pending[row.key]).flat().forEach((p) => URL.revokeObjectURL(p.url))
      setPending((p) => { const n = { ...p }; delete n[row.key]; return n })
    }
    setForm((p) => ({ ...p, [list]: p[list].filter((_, j) => j !== i) }))
  }

  const savedPhotos = (part, stage) => (part.id ? photos.filter((ph) => ph.itemId === part.id && ph.stage === stage) : [])
  const pendingPhotos = (part, stage) => pending[part.key]?.[stage] || []

  // A saved part's photos upload straight away; a new part's wait until the record is saved.
  const addPhotos = async (part, stage, fileList) => {
    const files = Array.from(fileList || []).filter((f) => {
      if (!ACCEPTED.includes(f.type)) { setErrors((p) => ({ ...p, photos: `${f.name}: only JPEG, PNG, WEBP, or HEIC images are allowed.` })); return false }
      if (f.size > MAX_SIZE) { setErrors((p) => ({ ...p, photos: `${f.name}: exceeds the 10 MB limit.` })); return false }
      return true
    })
    if (files.length === 0) return
    setErrors((p) => { const n = { ...p }; delete n.photos; return n })
    if (!part.id) {
      setPending((p) => ({
        ...p,
        [part.key]: { ...p[part.key], [stage]: [...(p[part.key]?.[stage] || []), ...files.map((file) => ({ file, url: URL.createObjectURL(file) }))] },
      }))
      return
    }
    setUploading(`${part.key}:${stage}`)
    try {
      for (const file of files) {
        const { data } = await uploadMaintenancePhoto(initial.id, file, { stage, itemId: part.id })
        setPhotos((p) => [data, ...p])
      }
    } catch (err) {
      setErrors((p) => ({ ...p, photos: err.response?.data?.message || 'Failed to upload the photo.' }))
    } finally {
      setUploading(null)
    }
  }

  const removePending = (part, stage, item) => {
    URL.revokeObjectURL(item.url)
    setPending((p) => ({ ...p, [part.key]: { ...p[part.key], [stage]: p[part.key][stage].filter((x) => x !== item) } }))
  }

  const removeSaved = async () => {
    const photo = removing
    setRemoving(null)
    try {
      await deleteMaintenancePhoto(initial.id, photo.id)
      setPhotos((p) => p.filter((x) => x.id !== photo.id))
    } catch (err) {
      setErrors((p) => ({ ...p, photos: err.response?.data?.message || 'Failed to delete the photo.' }))
    }
  }

  // Parts still missing a photo the completed repair needs (the server checks the same).
  const missingPhotos = () => parts.flatMap((p, i) => {
    const has = (stage) => savedPhotos(p, stage).length + pendingPhotos(p, stage).length > 0
    const before = p.additional || has('BEFORE')
    const after = has('AFTER')
    if (before && after) return []
    const what = !before && !after ? 'pre- and post-maintenance' : !before ? 'pre-maintenance' : 'post-maintenance'
    return [`${p.particular.trim() || `Part ${i + 1}`} (${what})`]
  })

  const payloadOf = (lines, status) => ({
    assetId: Number(form.assetId),
    maintenanceType: form.maintenanceType,
    findings: form.findings.trim(),
    actionsTaken: form.actionsTaken.trim(),
    assignedTo: form.assignedTo.trim() || null,
    maintenanceDate: form.maintenanceDate,
    completedDate: status === 'COMPLETED' ? form.completedDate : null,
    cost: hasLines ? linesTotal : Number(form.cost),
    status,
    items: [
      ...lines.parts.map((p) => ({ id: p.id, kind: 'PART', particular: p.particular.trim(), unit: p.unit.trim() || null, quantity: num(p.quantity), unitCost: num(p.unitCost), additional: !!p.additional })),
      ...lines.labor.map((l) => ({ id: l.id, kind: 'LABOR', particular: l.particular.trim(), totalCost: num(l.totalCost) })),
    ],
  })

  // The saved record's lines come back in the order sent, so each row takes its saved id.
  const withSavedIds = (lines, saved) => {
    const savedParts = (saved?.items || []).filter((i) => i.kind !== 'LABOR')
    const savedLabor = (saved?.items || []).filter((i) => i.kind === 'LABOR')
    return {
      parts: lines.parts.map((p, i) => ({ ...p, id: savedParts[i]?.id ?? p.id })),
      labor: lines.labor.map((l, i) => ({ ...l, id: savedLabor[i]?.id ?? l.id })),
    }
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = {}
    if (!form.assetId) errs.assetId = 'Asset is required.'
    if (!form.findings.trim()) errs.findings = 'Findings are required.'
    if (!form.actionsTaken.trim()) errs.actionsTaken = 'Actions taken are required.'
    if (!form.maintenanceDate) errs.maintenanceDate = 'Date is required.'
    if (form.status === 'COMPLETED') {
      if (!form.completedDate) errs.completedDate = 'Enter the date the maintenance was completed.'
      else if (form.maintenanceDate && form.completedDate < form.maintenanceDate) errs.completedDate = "It can't be before the maintenance date."
      else if (form.completedDate > todayKey()) errs.completedDate = "It can't be in the future."
    }
    if (!hasLines && !form.cost && form.cost !== 0) errs.cost = 'Enter the cost, or add the parts and labor below.'
    const badPart = parts.findIndex((p) => !p.particular.trim() || num(p.quantity) <= 0 || p.unitCost === '')
    const badLabor = labor.findIndex((l) => !l.particular.trim() || l.totalCost === '')
    if (badPart >= 0) errs.lines = `Part ${badPart + 1}: enter the particular, a quantity and the unit cost.`
    else if (badLabor >= 0) errs.lines = `Labor ${badLabor + 1}: enter the particular and the cost.`
    if (completing && parts.length > 0) {
      const missing = missingPhotos()
      if (missing.length) errs.photos = `Add the photos missing for these parts before marking the repair Completed: ${missing.join(', ')}.`
    }
    if (Object.keys(errs).length) { setErrors(errs); return }
    setSaving(true)
    try {
      if (!isEditing) {
        await onSave(payloadOf({ parts, labor }, form.status), idempotencyKey)
      } else {
        const keysWithPhotos = Object.keys(pending).filter((k) => Object.values(pending[k]).some((l) => l.length))
        // New parts need saving before their photos can go up, and a repair is only accepted as
        // Completed once its photos are there: so save it as it was first, upload, then complete.
        const twoSteps = completing && keysWithPhotos.length > 0
        let lines = { parts, labor }
        let saved = await onSave(payloadOf(lines, twoSteps ? initial.status : form.status))
        lines = withSavedIds(lines, saved)
        setForm((p) => ({ ...p, ...lines }))
        for (const part of lines.parts) {
          for (const stage of ['BEFORE', 'AFTER']) {
            for (const item of pending[part.key]?.[stage] || []) {
              const { data } = await uploadMaintenancePhoto(initial.id, item.file, { stage, itemId: part.id })
              setPhotos((p) => [data, ...p])
              removePending(part, stage, item)
            }
          }
        }
        if (twoSteps) saved = await onSave(payloadOf(lines, form.status))
      }
      draft.clear()
      onSaved?.()
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
              {/* a new record can't start as Completed: its photos are added after it is saved */}
              {MAINT_STATUS.filter((s) => isEditing || s !== 'COMPLETED').map((s) => <option key={s} value={s}>{s}</option>)}
            </SelectInput>
            {completing && (
              <p className="text-xs text-slate-500 dark:text-zinc-400">
                {parts.length > 0
                  ? 'Each part needs its pre- and post-maintenance photos (additional parts only post-maintenance). A repairable asset goes back to New, Good, or Serviceable by its age.'
                  : 'Needs at least one pre-maintenance and one post-maintenance photo (Photos). A repairable asset goes back to New, Good, or Serviceable by its age.'}
              </p>
            )}
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

        {form.status === 'COMPLETED' && (
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Date Completed<span className="text-red-400 ml-0.5">*</span></label>
              <DatePicker required className={INPUT_CLASS} value={form.completedDate} onChange={set('completedDate')}
                min={form.maintenanceDate || undefined} max={todayKey()} />
              {errors.completedDate && <p className="text-xs text-red-400">{errors.completedDate}</p>}
            </div>
          </div>
        )}

        {/* Parts and labor, as on the Repair and Maintenance Card */}
        <fieldset className="rounded-lg border border-slate-200 dark:border-zinc-800 p-4 space-y-4">
          <legend className="px-1 text-sm font-semibold text-slate-700 dark:text-zinc-300">Parts and labor</legend>
          <p className="text-xs text-slate-500 dark:text-zinc-400 -mt-2">
            List each damaged part with a pre-maintenance photo. When the repair is done, add a post-maintenance photo of each
            replacement part, and any additional part needed with its photo. The cost of repair is the total of the parts and labor.
            Leave both empty to type the cost yourself.
          </p>

          <div className="space-y-2">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">Parts</p>
            {parts.map((p, i) => (
              <div key={p.key} className="rounded-md border border-slate-200 dark:border-zinc-800 p-3 grid grid-cols-1 lg:grid-cols-12 gap-3">
                <div className="lg:col-span-7 space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs font-medium text-slate-500 dark:text-zinc-400">
                      Part {i + 1}
                      {p.additional && <span className="ml-2 rounded px-1.5 py-0.5 bg-brand-500/10 text-brand-700 dark:text-brand-300">Additional part</span>}
                    </span>
                    <button type="button" onClick={() => removeLine('parts', i)} aria-label={`Remove part ${i + 1}`} className="p-1.5 rounded-md text-slate-400 hover:text-red-500 hover:bg-red-500/10">
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
                    </button>
                  </div>
                  <input aria-label={`Part ${i + 1} particular`} className={INPUT_CLASS} placeholder="e.g. Oil Filter" value={p.particular} onChange={setLine('parts', i, 'particular')} maxLength={255} />
                  <div className="grid grid-cols-12 gap-2 items-center">
                    <label className="col-span-3 text-xs text-slate-500 dark:text-zinc-400">Unit
                      <input aria-label={`Part ${i + 1} unit`} className={`${INPUT_CLASS} mt-1`} placeholder="pc" value={p.unit} onChange={setLine('parts', i, 'unit')} maxLength={30} />
                    </label>
                    <label className="col-span-3 text-xs text-slate-500 dark:text-zinc-400">Qty
                      <input aria-label={`Part ${i + 1} quantity`} type="number" min="0" step="any" className={`${INPUT_CLASS} mt-1 px-2`} value={p.quantity} onChange={setLine('parts', i, 'quantity')} />
                    </label>
                    <label className="col-span-3 text-xs text-slate-500 dark:text-zinc-400">Unit cost
                      <input aria-label={`Part ${i + 1} unit cost`} type="number" min="0" step="0.01" className={`${INPUT_CLASS} mt-1`} placeholder="0.00" value={p.unitCost} onChange={setLine('parts', i, 'unitCost')} />
                    </label>
                    <div className="col-span-3 text-xs text-slate-500 dark:text-zinc-400 text-right">Total
                      <p className="mt-1 py-2.5 text-sm tabular-nums text-slate-700 dark:text-zinc-200">{peso(partTotal(p))}</p>
                    </div>
                  </div>
                </div>
                <div className="lg:col-span-5 grid grid-cols-2 gap-3">
                  {STAGES.map((st) => (
                    st.key === 'BEFORE' && p.additional ? (
                      <div key={st.key}>
                        <p className="text-xs font-medium text-slate-700 dark:text-zinc-300">{st.label}</p>
                        <p className="mt-1 text-xs text-slate-400 dark:text-zinc-500">Not needed for an additional part.</p>
                      </div>
                    ) : (
                      <PartPhotos
                        key={st.key}
                        label={st.label}
                        hint={st.hint}
                        part={i + 1}
                        saved={savedPhotos(p, st.key)}
                        waiting={pendingPhotos(p, st.key)}
                        busy={uploading === `${p.key}:${st.key}`}
                        disabled={!isEditing || saving || uploading != null}
                        onAdd={(files) => addPhotos(p, st.key, files)}
                        onRemoveSaved={setRemoving}
                        onRemoveWaiting={(item) => removePending(p, st.key, item)}
                        onOpen={setPreview}
                      />
                    )
                  ))}
                </div>
              </div>
            ))}
            <div className="flex flex-wrap gap-2">
              <Button type="button" variant="secondary" size="sm" onClick={() => addLine('parts')}>Add damaged part</Button>
              {isEditing && (
                <Button type="button" variant="secondary" size="sm" onClick={() => addLine('parts', { additional: true })}>Add additional part</Button>
              )}
            </div>
            {!isEditing && parts.length > 0 && (
              <p className="text-xs text-slate-500 dark:text-zinc-400">Photos can be added once the record is saved.</p>
            )}
            {errors.photos && <p className="text-xs text-red-400">{errors.photos}</p>}
          </div>

          <div className="space-y-2">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">Labor</p>
            {labor.map((l, i) => (
              <div key={l.key} className="grid grid-cols-12 gap-2 items-center">
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
          <Button type="submit" size="md" disabled={saving || uploading != null}>{saving ? 'Saving…' : isEditing ? 'Save Changes' : 'Add Record'}</Button>
        </div>
      </form>

      {preview && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center p-6 bg-black/80" onClick={() => setPreview(null)}>
          <img src={preview} alt="Part photo" className="max-h-full max-w-full rounded-lg shadow-2xl" />
        </div>
      )}
      {removing && (
        <ConfirmDialog
          title="Delete this photo?"
          message="This part photo will be permanently removed."
          confirmLabel="Delete"
          onConfirm={removeSaved}
          onCancel={() => setRemoving(null)}
        />
      )}
    </Modal>
  )
}

// One part's photos for one stage: saved ones, ones waiting for the record to be saved, and an add tile.
function PartPhotos({ label, hint, part, saved, waiting, busy, disabled, onAdd, onRemoveSaved, onRemoveWaiting, onOpen }) {
  const inputRef = useRef(null)
  const thumb = 'group relative h-14 w-14 rounded-md overflow-hidden bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700'
  const removeBtn = 'absolute top-0.5 right-0.5 p-0.5 rounded bg-black/60 text-white opacity-0 group-hover:opacity-100 focus:opacity-100 hover:bg-red-600'
  const x = <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
  return (
    <div>
      <p className="text-xs font-medium text-slate-700 dark:text-zinc-300">{label}</p>
      <p className="text-2xs text-slate-400 dark:text-zinc-500">{hint}</p>
      <input ref={inputRef} type="file" accept={ACCEPTED.join(',')} multiple className="hidden"
        onChange={(e) => { onAdd(e.target.files); e.target.value = '' }} />
      <div className="mt-1.5 flex flex-wrap gap-1.5">
        {saved.map((ph) => (
          <div key={ph.id} className={thumb}>
            <img src={resolveUploadUrl(ph.url)} alt={`${label} photo of part ${part}`} className="h-full w-full object-cover cursor-pointer" onClick={() => onOpen(resolveUploadUrl(ph.url))} />
            <button type="button" aria-label="Delete photo" className={removeBtn} onClick={() => onRemoveSaved(ph)}>{x}</button>
          </div>
        ))}
        {waiting.map((item) => (
          <div key={item.url} className={thumb} title="Uploads when you save">
            <img src={item.url} alt={`${label} photo of part ${part}, not uploaded yet`} className="h-full w-full object-cover opacity-70 cursor-pointer" onClick={() => onOpen(item.url)} />
            <button type="button" aria-label="Remove photo" className={removeBtn} onClick={() => onRemoveWaiting(item)}>{x}</button>
          </div>
        ))}
        <button type="button" disabled={disabled} onClick={() => inputRef.current?.click()}
          aria-label={`Add ${label.toLowerCase()} photo for part ${part}`}
          className="h-14 w-14 flex flex-col items-center justify-center rounded-md border-2 border-dashed border-slate-200 dark:border-zinc-700 text-slate-400 dark:text-zinc-500 hover:border-brand-500/50 hover:text-brand-600 disabled:opacity-50 disabled:cursor-not-allowed">
          <svg xmlns="http://www.w3.org/2000/svg" className={`h-4 w-4 ${busy ? 'animate-pulse' : ''}`} viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fillRule="evenodd" d="M4 5a2 2 0 00-2 2v8a2 2 0 002 2h12a2 2 0 002-2V7a2 2 0 00-2-2h-1.586a1 1 0 01-.707-.293l-1.121-1.121A2 2 0 0011.172 3H8.828a2 2 0 00-1.414.586L6.293 4.707A1 1 0 015.586 5H4zm6 9a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
          </svg>
          <span className="text-2xs mt-0.5">{busy ? '…' : 'Add'}</span>
        </button>
      </div>
    </div>
  )
}

export default AddMaintenanceModal
