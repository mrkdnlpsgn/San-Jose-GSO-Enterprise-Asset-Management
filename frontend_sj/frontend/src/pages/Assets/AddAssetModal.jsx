import { useState, useEffect, useRef } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import { createCategory } from '../../services/categoryService'
import { scanAssetLabel } from '../../services/assetService'
import { useToast } from '../../context/ToastContext'
import { newIdempotencyKey } from '../../utils/idempotency'

const PREDEFINED_CATEGORIES = ['Appliances', 'Vehicle', 'Office Supplies']
const CONDITIONS  = ['SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE']
const INPUT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

export default function AddAssetModal({ onClose, onSave, initial = null, categories = [], offices = [], onCategoryCreated }) {
  const isEditing = !!initial
  const toast = useToast()
  const cameraInputRef = useRef(null)
  const uploadInputRef = useRef(null)
  const [scanning, setScanning] = useState(false)
  const [wasScanned, setWasScanned] = useState(false)

  const [form, setForm] = useState({
    propertyNumber:   initial?.propertyNumber      || '',
    serialNumber:     initial?.serialNumber        || '',
    description:      initial?.description         || '',
    categoryId:       initial?.category?.id        ? String(initial.category.id) : '',
    quantity:         initial?.quantity             ?? 1,
    acquisitionDate:  initial?.acquisitionDate      || '',
    unitValue:        initial?.unitValue            ?? '',
    officeId:         initial?.office?.id           ? String(initial.office.id) : '',
    accountablePerson: initial?.accountablePerson   || '',
    physicalCount:    initial?.physicalCount         ?? 1,
    location:         initial?.location             || '',
    condition:        initial?.condition            || 'SERVICEABLE',
    lifecycleStatus:  initial?.lifecycleStatus      || 'REGISTERED',
    remarks:          initial?.remarks              || '',
  })
  const [errors, setErrors]         = useState({})
  const [saving, setSaving]         = useState(false)
  const [idempotencyKey] = useState(() => newIdempotencyKey())

  // Custom category state
  const [customMode, setCustomMode]       = useState(false)
  const [customName, setCustomName]       = useState('')
  const [savingCustom, setSavingCustom]   = useState(false)
  const [customError, setCustomError]     = useState('')

  // Build combined category list: predefined first, then DB categories not already matching a predefined name
  const dbCategoryNames = categories.map((c) => c.categoryName.toLowerCase())
  const extraPredefined = PREDEFINED_CATEGORIES.filter(
    (p) => !dbCategoryNames.includes(p.toLowerCase())
  ).map((name) => ({ id: `pre:${name}`, categoryName: name, _predefined: true }))
  const allCategories = [...extraPredefined, ...categories]

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const handleCategoryChange = (e) => {
    const val = e.target.value
    if (val === '__custom__') {
      setCustomMode(true)
      setForm((p) => ({ ...p, categoryId: '' }))
    } else {
      setCustomMode(false)
      setForm((p) => ({ ...p, categoryId: val }))
      setErrors((p) => { const n = { ...p }; delete n.categoryId; return n })
    }
  }

  const handleSaveCustomCategory = async () => {
    const name = customName.trim()
    if (!name) { setCustomError('Category name is required.'); return }
    setSavingCustom(true)
    setCustomError('')
    try {
      const { data: newCat } = await createCategory({ categoryName: name, description: '' }, idempotencyKey)
      if (onCategoryCreated) onCategoryCreated(newCat)
      setForm((p) => ({ ...p, categoryId: String(newCat.id) }))
      setCustomMode(false)
      setCustomName('')
      setErrors((p) => { const n = { ...p }; delete n.categoryId; return n })
    } catch (err) {
      setCustomError(err.response?.data?.message || 'Failed to create category.')
    } finally {
      setSavingCustom(false)
    }
  }

  const handleScanLabel = async (e) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setScanning(true)
    try {
      const { data } = await scanAssetLabel(file)
      setForm((p) => ({
        ...p,
        description: data.description || p.description,
        serialNumber: data.serialNumber || p.serialNumber,
      }))
      setWasScanned(true)
      toast.show('Label scanned — review the details below.', 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to scan label.', 'error')
    } finally {
      setScanning(false)
    }
  }

  const validate = () => {
    const e = {}
    if (!form.description.trim())      e.description      = 'Description is required.'
    if (!form.categoryId)              e.categoryId       = 'Category is required.'
    if (!form.officeId)                e.officeId         = 'Location is required.'
    if (!form.accountablePerson.trim()) e.accountablePerson = 'Accountable person is required.'
    if (form.physicalCount === '' || form.physicalCount == null) e.physicalCount = 'Physical count is required.'
    if (!form.acquisitionDate)         e.acquisitionDate  = 'Acquisition date is required.'
    if (!form.unitValue && form.unitValue !== 0) e.unitValue = 'Unit value is required.'
    return e
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = validate()
    if (Object.keys(errs).length) { setErrors(errs); return }
    setSaving(true)
    try {
      // Resolve category ID — predefined-only entries need to be created first
      let resolvedCategoryId = Number(form.categoryId)
      if (form.categoryId.startsWith?.('pre:')) {
        const name = form.categoryId.replace('pre:', '')
        const { data: newCat } = await createCategory({ categoryName: name, description: '' }, idempotencyKey)
        if (onCategoryCreated) onCategoryCreated(newCat)
        resolvedCategoryId = newCat.id
      }

      const selectedOfficeName = offices.find((o) => String(o.id) === String(form.officeId))?.officeName || ''
      const payload = {
        propertyNumber:    form.propertyNumber.trim() || null,
        serialNumber:      form.serialNumber.trim() || null,
        description:       form.description.trim(),
        categoryId:        resolvedCategoryId,
        quantity:          Number(form.quantity) || 1,
        acquisitionDate:   form.acquisitionDate,
        unitValue:         Number(form.unitValue),
        officeId:          Number(form.officeId),
        accountablePerson: form.accountablePerson.trim(),
        physicalCount:     form.physicalCount !== '' ? Number(form.physicalCount) : null,
        location:          selectedOfficeName,
        condition:         form.condition,
        ...(isEditing ? { lifecycleStatus: form.lifecycleStatus } : {}),
        remarks:           form.remarks.trim() || null,
      }
      await onSave(payload, idempotencyKey, wasScanned)
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save asset.' })
    } finally {
      setSaving(false)
    }
  }

  const conditionNote = form.condition === 'REPAIRABLE'
    ? { color: 'amber', text: 'A maintenance ledger record will be automatically created.' }
    : form.condition === 'UNSERVICEABLE'
    ? { color: 'red',   text: 'A disposal ledger record will be automatically created.' }
    : null

  return (
    <Modal title={isEditing ? 'Edit Asset' : 'Add Asset'} size="lg" onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}

        {!isEditing && (
          <div>
            <input
              ref={cameraInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              capture="environment"
              className="hidden"
              onChange={handleScanLabel}
            />
            <input
              ref={uploadInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              className="hidden"
              onChange={handleScanLabel}
            />
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                disabled={scanning}
                onClick={() => cameraInputRef.current?.click()}
                className="flex items-center justify-center gap-2 rounded-lg border-2 border-dashed border-slate-200 dark:border-zinc-700 hover:border-brand-500/50 hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-all duration-150 py-3 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className={`h-4 w-4 text-slate-400 dark:text-zinc-500 ${scanning ? 'animate-pulse' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 17a4 4 0 100-8 4 4 0 000 8z" />
                </svg>
                <span className="text-sm font-medium text-slate-500 dark:text-zinc-400">
                  {scanning ? 'Scanning…' : 'Take Photo'}
                </span>
              </button>
              <button
                type="button"
                disabled={scanning}
                onClick={() => uploadInputRef.current?.click()}
                className="flex items-center justify-center gap-2 rounded-lg border-2 border-dashed border-slate-200 dark:border-zinc-700 hover:border-brand-500/50 hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-all duration-150 py-3 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className={`h-4 w-4 text-slate-400 dark:text-zinc-500 ${scanning ? 'animate-pulse' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 8.25L12 3.75m0 0L7.5 8.25M12 3.75v12.75" />
                </svg>
                <span className="text-sm font-medium text-slate-500 dark:text-zinc-400">
                  {scanning ? 'Scanning…' : 'Upload Image'}
                </span>
              </button>
            </div>
            <p className="text-2xs text-slate-400 dark:text-zinc-600 mt-1.5">
              Scan a device label/sticker to auto-fill the description and serial number below.
            </p>
          </div>
        )}

        {/* Property No. + Serial No. */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Property Number <span className="text-slate-400 font-normal">(optional)</span></label>
            <input className={INPUT_CLASS} placeholder="Leave blank to auto-generate" value={form.propertyNumber} onChange={set('propertyNumber')} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Serial Number <span className="text-slate-400 font-normal">(optional)</span></label>
            <input className={INPUT_CLASS} placeholder="Manufacturer serial number" value={form.serialNumber} onChange={set('serialNumber')} />
          </div>
        </div>

        {/* Category */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Category<span className="text-red-400 ml-0.5">*</span></label>
          {customMode ? (
              <div className="space-y-2">
                <div className="flex gap-2">
                  <input
                    className={INPUT_CLASS}
                    placeholder="Enter new category name…"
                    value={customName}
                    onChange={(e) => { setCustomName(e.target.value); setCustomError('') }}
                    autoFocus
                  />
                  <button
                    type="button"
                    onClick={handleSaveCustomCategory}
                    disabled={savingCustom}
                    className="flex-shrink-0 px-3 py-2.5 rounded-md bg-brand-500 text-white text-sm font-semibold hover:bg-brand-600 disabled:opacity-50 transition-all"
                  >
                    {savingCustom ? '…' : 'Add'}
                  </button>
                  <button
                    type="button"
                    onClick={() => { setCustomMode(false); setCustomName(''); setCustomError('') }}
                    className="flex-shrink-0 px-3 py-2.5 rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 text-sm hover:bg-slate-50 dark:hover:bg-zinc-800 transition-all"
                  >
                    Cancel
                  </button>
                </div>
                {customError && <p className="text-xs text-red-400">{customError}</p>}
              </div>
            ) : (
              <div className="relative">
                <select
                  className={INPUT_CLASS + ' appearance-none pr-9'}
                  value={form.categoryId}
                  onChange={handleCategoryChange}
                >
                  <option value="">— Select category —</option>
                  {allCategories.map((c) => (
                    <option key={c.id} value={String(c.id)}>{c.categoryName}</option>
                  ))}
                  <option value="__custom__">＋ Add custom category…</option>
                </select>
                <ChevronIcon />
              </div>
            )}
          {errors.categoryId && !customMode && <p className="text-xs text-red-400">{errors.categoryId}</p>}
        </div>

        {/* Description */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Description<span className="text-red-400 ml-0.5">*</span></label>
          <input className={INPUT_CLASS} placeholder="Article / equipment description" value={form.description} onChange={set('description')} />
          {errors.description && <p className="text-xs text-red-400">{errors.description}</p>}
        </div>

        {/* Qty + Physical Count + Acq Date + Unit Value */}
        <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300 min-h-[2.5rem] flex items-start">Qty (Property Card)</label>
            <input type="number" min="1" className={INPUT_CLASS} value={form.quantity} onChange={set('quantity')} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300 min-h-[2.5rem] flex items-start">Qty (Physical Count)<span className="text-red-400 ml-0.5">*</span></label>
            <input type="number" min="0" className={INPUT_CLASS} placeholder="0" value={form.physicalCount} onChange={set('physicalCount')} />
            {errors.physicalCount && <p className="text-xs text-red-400">{errors.physicalCount}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300 min-h-[2.5rem] flex items-start">Acquisition Date<span className="text-red-400 ml-0.5">*</span></label>
            <input type="date" className={INPUT_CLASS} value={form.acquisitionDate} onChange={set('acquisitionDate')} />
            {errors.acquisitionDate && <p className="text-xs text-red-400">{errors.acquisitionDate}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300 min-h-[2.5rem] flex items-start">Unit Value (₱)<span className="text-red-400 ml-0.5">*</span></label>
            <input type="number" min="0" step="0.01" className={INPUT_CLASS} placeholder="0.00" value={form.unitValue} onChange={set('unitValue')} />
            {errors.unitValue && <p className="text-xs text-red-400">{errors.unitValue}</p>}
          </div>
        </div>

        {/* Location + Accountable Person */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Location<span className="text-red-400 ml-0.5">*</span></label>
            <div className="relative">
              <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.officeId} onChange={set('officeId')}>
                <option value="">— Select location —</option>
                {offices.map((o) => <option key={o.id} value={String(o.id)}>{o.officeName}</option>)}
              </select>
              <ChevronIcon />
            </div>
            {errors.officeId && <p className="text-xs text-red-400">{errors.officeId}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Accountable Person<span className="text-red-400 ml-0.5">*</span></label>
            <input
              className={INPUT_CLASS}
              placeholder="Full name of accountable person"
              value={form.accountablePerson}
              onChange={set('accountablePerson')}
            />
            {errors.accountablePerson && <p className="text-xs text-red-400">{errors.accountablePerson}</p>}
          </div>
        </div>

        {/* Condition */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Condition<span className="text-red-400 ml-0.5">*</span></label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.condition} onChange={set('condition')}>
              {CONDITIONS.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
            <ChevronIcon />
          </div>
        </div>

        {conditionNote && (
          <div className={`flex items-start gap-2.5 px-4 py-3 rounded-lg border ${
            conditionNote.color === 'amber'
              ? 'bg-amber-500/8 border-amber-500/20 text-amber-400'
              : 'bg-red-500/8 border-red-500/20 text-red-400'
          }`}>
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 flex-shrink-0 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
            </svg>
            <p className="text-xs font-medium">{conditionNote.text}</p>
          </div>
        )}

        {/* Remarks */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Remarks <span className="text-slate-400 font-normal">(optional)</span></label>
          <textarea className={INPUT_CLASS + ' resize-none'} rows={2} placeholder="Additional notes…" value={form.remarks} onChange={set('remarks')} />
        </div>

        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : isEditing ? 'Save Changes' : 'Add Asset'}</Button>
        </div>
      </form>
    </Modal>
  )
}

function ChevronIcon() {
  return (
    <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
      </svg>
    </div>
  )
}
