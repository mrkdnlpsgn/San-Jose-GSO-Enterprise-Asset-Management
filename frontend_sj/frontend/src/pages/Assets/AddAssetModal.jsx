import { useState, useEffect, useRef } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import CameraCaptureModal from '../../components/common/CameraCaptureModal'
import { createCategory } from '../../services/categoryService'
import { scanAssetLabel } from '../../services/assetService'
import { useToast } from '../../context/ToastContext'
import { newIdempotencyKey } from '../../utils/idempotency'

const PREDEFINED_CATEGORIES = ['Appliances', 'Vehicle', 'Office Supplies']
const CONDITIONS  = ['SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE']
const PAR_SERIAL_RE = /^[A-Za-z0-9-]+$/

// PAR number = acquisition year-month + ':' + a serial typed by hand,
// e.g. "2026-07:H78JD80". The prefix is derived from the Acquisition Date field
// rather than typed, so the two can never disagree.
const parPrefix = (acquisitionDate) => (acquisitionDate ? acquisitionDate.slice(0, 7) : '')

// Qty (Property Card) N means N devices, and every device is its own complete asset:
// its own Property Number and PAR Number (the unique identifiers) plus — optionally —
// its own serial, price, date, location, accountable person, current user, condition,
// specs and remarks. Whatever a device leaves blank is inherited from the shared
// details above, so a batch of identical devices only needs the two numbers typed.
const MAX_UNITS = 500
const blankUnit = () => ({
  propertyNumber: '', parSerial: '', serialNumber: '', unitValue: '', acquisitionDate: '',
  officeId: '', personnelId: '', currentUserId: '', condition: '', specifications: '', remarks: '',
})
const resizeUnits = (units, n) =>
  Number.isInteger(n) && n >= 1 && n <= MAX_UNITS
    ? Array.from({ length: n }, (_, i) => units[i] || blankUnit())
    : units
// When editing, device 1 is the asset being edited (numbers pre-filled); any further
// devices are new assets that will be added to the same group.
const firstUnitFromAsset = (a) => ({
  ...blankUnit(),
  propertyNumber: a?.propertyNumber || '',
  parSerial: a?.parNumber?.includes(':') ? a.parNumber.split(':').slice(1).join(':') : '',
  // With several devices these live on each device (the shared form hides them), so
  // device 1 starts from this asset's own values.
  unitValue: a?.unitValue != null ? String(a.unitValue) : '',
  acquisitionDate: a?.acquisitionDate || '',
  condition: a?.condition || '',
  specifications: a?.specifications || '',
  officeId: a?.office?.id ? String(a.office.id) : '',
  personnelId: a?.accountablePerson?.id ? String(a.accountablePerson.id) : '',
  currentUserId: a?.currentUser?.id ? String(a.currentUser.id) : '',
})

const INPUT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

// staffMode: a STAFF account editing an asset of its office — it can't move the asset to
// another office, add devices, or create categories (all admin-only).
export default function AddAssetModal({ onClose, onSave, initial = null, categories = [], offices = [], personnel = [], onCategoryCreated, staffMode = false }) {
  const isEditing = !!initial
  // A device inside a group is always exactly one unit — Qty (Property Card) and Qty (Physical
  // Count) are fixed at 1 and can't be changed.
  const lockedQty = !!initial?.groupId || staffMode
  const toast = useToast()
  const uploadInputRef = useRef(null)
  const [scanning, setScanning] = useState(false)
  const [wasScanned, setWasScanned] = useState(false)
  const [showCamera, setShowCamera] = useState(false)

  const [form, setForm] = useState({
    serialNumber:     initial?.serialNumber        || '',
    description:      initial?.description         || '',
    categoryId:       initial?.category?.id        ? String(initial.category.id) : '',
    quantity:         initial?.groupId ? 1 : (initial?.quantity ?? 1),
    acquisitionDate:  initial?.acquisitionDate      || '',
    unitValue:        initial?.unitValue            ?? '',
    officeId:         initial?.office?.id           ? String(initial.office.id) : '',
    personnelId:      initial?.accountablePerson?.id ? String(initial.accountablePerson.id) : '',
    currentUserId:    initial?.currentUser?.id       ? String(initial.currentUser.id) : '',
    physicalCount:    initial?.groupId ? 1 : (initial?.physicalCount ?? 1),
    units:            resizeUnits(initial ? [firstUnitFromAsset(initial)] : [], initial?.quantity ?? 1),
    location:         initial?.location             || '',
    condition:        initial?.condition            || 'SERVICEABLE',
    lifecycleStatus:  initial?.lifecycleStatus      || 'REGISTERED',
    specifications:   initial?.specifications       || '',
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

  // Once an office is selected, narrow both the Accountable Person and Current
  // User dropdowns to personnel assigned to that office — before that, show
  // everyone so picking an office isn't forced before picking a person.
  // deactivated accounts can't take on assets (an asset already assigned to one still shows it — see keepSelected)
  const activePersonnel = personnel.filter((p) => p.userActive !== false)
  const personnelForOffice = form.officeId
    ? activePersonnel.filter((p) => String(p.office?.id) === String(form.officeId))
    : activePersonnel

  const keepSelected = (list, person) =>
    person && !list.some((p) => p.id === person.id) ? [...list, { ...person, _former: true }] : list
  const accountableOptions = keepSelected(personnelForOffice, initial?.accountablePerson)
  const currentUserOptions = keepSelected(personnelForOffice, initial?.currentUser)

  const personnelFor = (officeId) =>
    officeId ? activePersonnel.filter((p) => String(p.office?.id) === String(officeId)) : activePersonnel

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  // Physical Count must equal Qty (Property Card), so it follows the quantity as
  // it's typed (still editable, still validated), and the unit list resizes to match.
  const handleQuantityChange = (e) => {
    const val = e.target.value
    const n = parseInt(val, 10)
    setForm((p) => {
      const units = resizeUnits(p.units, n)
      if (!Number.isInteger(n) || n < 1 || n > MAX_UNITS) return { ...p, quantity: val, physicalCount: val, units }
      if (n > 1) {
        // The shared Condition / Specifications / Unit Value fields are replaced by per-device
        // ones — carry whatever was already typed over so nothing is lost.
        return {
          ...p, quantity: val, physicalCount: val,
          units: units.map((u) => ({
            ...u,
            condition: u.condition || p.condition || 'SERVICEABLE',
            specifications: u.specifications || p.specifications || '',
            officeId: u.officeId || p.officeId || '',
            personnelId: u.personnelId || p.personnelId || '',
            currentUserId: u.currentUserId || p.currentUserId || '',
            unitValue: u.unitValue !== '' ? u.unitValue : (p.unitValue !== '' && p.unitValue != null ? String(p.unitValue) : ''),
          })),
        }
      }
      // Back to a single asset: the shared fields come back, seeded from device 1.
      const u0 = p.units[0] || blankUnit()
      return {
        ...p, quantity: val, physicalCount: val, units,
        condition: u0.condition || p.condition,
        specifications: u0.specifications || p.specifications,
        officeId: u0.officeId || p.officeId,
        personnelId: u0.personnelId || p.personnelId,
        currentUserId: u0.currentUserId || p.currentUserId,
        unitValue: u0.unitValue !== '' ? u0.unitValue : p.unitValue,
        acquisitionDate: p.acquisitionDate || u0.acquisitionDate,
      }
    })
    setErrors((p) => { const n2 = { ...p }; delete n2.quantity; delete n2.physicalCount; return n2 })
  }

  const setUnit = (i, key) => (e) => {
    const val = e.target.value
    setForm((p) => ({ ...p, units: p.units.map((u, idx) => (idx === i ? { ...u, [key]: val } : u)) }))
    setErrors((p) => { const n = { ...p }; delete n[`unit${i}`]; delete n[`unitv${i}`]; delete n[`unitd${i}`]; delete n[`unito${i}`]; delete n[`unitp${i}`]; return n })
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

  const handlePersonnelChange = (e) => {
    const val = e.target.value
    setForm((p) => ({ ...p, personnelId: val }))
    setErrors((p) => { const n = { ...p }; delete n.personnelId; return n })
  }

  const scanFile = async (file) => {
    if (!file) return
    setScanning(true)
    try {
      const { data } = await scanAssetLabel(file)
      setForm((p) => ({
        ...p,
        description: data.description || p.description,
        serialNumber: data.serialNumber || p.serialNumber,
        specifications: data.specifications || p.specifications,
      }))
      setWasScanned(true)
      toast.show('Scanned — review the details below.', 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to scan label.', 'error')
    } finally {
      setScanning(false)
    }
  }

  const handleUploadChange = (e) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    scanFile(file)
  }

  const handleCameraCapture = (file) => {
    setShowCamera(false)
    scanFile(file)
  }

  const validate = () => {
    const e = {}
    const qty = Number(form.quantity)
    if (!Number.isInteger(qty) || qty < 1 || qty > MAX_UNITS) e.quantity = `Enter a whole number from 1 to ${MAX_UNITS}.`
    else if (Number(form.physicalCount) !== qty) e.physicalCount = 'Must equal Qty (Property Card).'
    const multi = form.units.length > 1
    form.units.forEach((u, i) => {
      const par = u.parSerial.trim()
      const date = form.acquisitionDate || u.acquisitionDate
      if (multi && !date)                 e[`unitd${i}`] = 'Set the Acquisition Date above for every device, or give this device its own.'
      if (multi && (u.unitValue === '' || !(Number(u.unitValue) >= 0))) e[`unitv${i}`] = 'Unit value is required.'
      if (multi && !u.officeId)     e[`unito${i}`] = 'Location is required.'
      if (multi && !u.personnelId)  e[`unitp${i}`] = 'Accountable person is required.'
      if (!date)                          e[`unit${i}`] = 'Pick the Acquisition Date first — the PAR Number starts with its year-month.'
      else if (!par)                      e[`unit${i}`] = 'PAR serial is required.'
      else if (!PAR_SERIAL_RE.test(par))  e[`unit${i}`] = 'PAR serial: letters, numbers, and hyphens only.'
      // Devices issued on one PAR share its number, so the same serial may repeat here.
    })
    if (!form.description.trim())      e.description      = 'Description is required.'
    if (!form.categoryId)              e.categoryId       = 'Category is required.'
    if (!multi && !form.officeId)      e.officeId         = 'Location is required.'
    if (!multi && !form.personnelId)   e.personnelId      = 'Accountable person is required.'
    if (form.physicalCount === '' || form.physicalCount == null) e.physicalCount = 'Physical count is required.'
    if (!multi && !form.acquisitionDate) e.acquisitionDate = 'Acquisition date is required.'
    if (!multi && !form.unitValue && form.unitValue !== 0) e.unitValue = 'Unit value is required.'
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

      const multi = form.units.length > 1
      // With several devices the shared Location / people fields are hidden (each device has its own);
      // the request still needs shared values, so they mirror device 1.
      const sharedOfficeId    = multi ? form.units[0].officeId : form.officeId
      const sharedPersonnelId = multi ? form.units[0].personnelId : form.personnelId
      const sharedCurrentUser = multi ? form.units[0].currentUserId : form.currentUserId
      const selectedOfficeName = offices.find((o) => String(o.id) === String(sharedOfficeId))?.officeName || ''
      // With several devices the shared Condition / Specs / Unit Value fields are hidden: each
      // device carries its own, and a shared Acquisition Date (if set) applies to all of them.
      // With one, the shared fields are the asset's own and the device entry only has numbers.
      const ov = (v) => (multi ? v : null)
      const payload = {
        units: form.units.map((u) => ({
          propertyNumber:  u.propertyNumber.trim() || null,
          parNumber:       `${parPrefix(form.acquisitionDate || u.acquisitionDate)}:${u.parSerial.trim()}`,
          serialNumber:    ov(u.serialNumber.trim() || null),
          unitValue:       ov(u.unitValue !== '' ? Number(u.unitValue) : null),
          acquisitionDate: multi && !form.acquisitionDate ? (u.acquisitionDate || null) : null,
          officeId:        ov(u.officeId ? Number(u.officeId) : null),
          personnelId:     ov(u.personnelId ? Number(u.personnelId) : null),
          currentUserId:   ov(u.currentUserId ? Number(u.currentUserId) : null),
          condition:       ov(u.condition || 'SERVICEABLE'),
          specifications:  ov(u.specifications.trim() || null),
          remarks:         ov(u.remarks.trim() || null),
        })),
        serialNumber:      form.serialNumber.trim() || null,
        description:       form.description.trim(),
        categoryId:        resolvedCategoryId,
        quantity:          Number(form.quantity) || 1,
        acquisitionDate:   form.acquisitionDate || null,
        unitValue:         multi ? totalUnitValue : Number(form.unitValue),
        officeId:          Number(sharedOfficeId),
        personnelId:       sharedPersonnelId ? Number(sharedPersonnelId) : null,
        currentUserId:     sharedCurrentUser ? Number(sharedCurrentUser) : null,
        physicalCount:     form.physicalCount !== '' ? Number(form.physicalCount) : null,
        location:          selectedOfficeName,
        condition:         multi ? 'SERVICEABLE' : form.condition,
        ...(isEditing ? { lifecycleStatus: form.lifecycleStatus } : {}),
        specifications:    multi ? null : (form.specifications.trim() || null),
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

  const isMulti = form.units.length > 1
  // With several devices the shared Unit Value is just the sum of the devices' own values.
  const totalUnitValue = form.units.reduce((n, u) => n + (Number(u.unitValue) || 0), 0)

  const conditionNote = !isMulti && form.condition === 'REPAIRABLE'
    ? { color: 'amber', text: 'A maintenance ledger record will be automatically created.' }
    : !isMulti && form.condition === 'UNSERVICEABLE'
    ? { color: 'red',   text: 'A disposal ledger record will be automatically created.' }
    : null

  return (
    <>
    {showCamera && (
      <CameraCaptureModal onCapture={handleCameraCapture} onClose={() => setShowCamera(false)} />
    )}
    <Modal title={isEditing ? 'Edit Asset' : 'Add Asset'} size="lg" onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}

        {!isEditing && (
          <div>
            <input
              ref={uploadInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              className="hidden"
              onChange={handleUploadChange}
            />
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                disabled={scanning}
                onClick={() => setShowCamera(true)}
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
              Scan a device label/sticker or a property document (e.g. a PAR with a Technical
              Specifications section) to auto-fill the description, serial number, and specifications below.
            </p>
          </div>
        )}

        {/* Serial No. — shared default; each unit can override it below */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">
            Serial Number <span className="text-slate-400 font-normal">(optional{Number(form.quantity) > 1 ? ' — default for every device; override per device below' : ''})</span>
          </label>
          <input className={INPUT_CLASS} placeholder="Manufacturer serial number" value={form.serialNumber} onChange={set('serialNumber')} />
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
                  {!staffMode && <option value="__custom__">＋ Add custom category…</option>}
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
            <input type="number" min="1" max={MAX_UNITS} disabled={lockedQty} className={INPUT_CLASS + (lockedQty ? ' opacity-60 cursor-not-allowed' : '')} value={form.quantity} onChange={handleQuantityChange} />
            {lockedQty && <p className="text-2xs text-slate-400 dark:text-zinc-600">{initial?.groupId ? 'Fixed at 1 for devices in a group.' : 'Only an administrator can add devices.'}</p>}
            {errors.quantity && <p className="text-xs text-red-400">{errors.quantity}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300 min-h-[2.5rem] flex items-start">Qty (Physical Count)<span className="text-red-400 ml-0.5">*</span></label>
            <input type="number" min="0" disabled={lockedQty} className={INPUT_CLASS + (lockedQty ? ' opacity-60 cursor-not-allowed' : '')} placeholder="0" value={form.physicalCount} onChange={set('physicalCount')} />
            {errors.physicalCount && <p className="text-xs text-red-400">{errors.physicalCount}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300 min-h-[2.5rem] flex items-start">Acquisition Date{!isMulti && <span className="text-red-400 ml-0.5">*</span>}</label>
            <input type="date" className={INPUT_CLASS} value={form.acquisitionDate} onChange={set('acquisitionDate')} />
            {errors.acquisitionDate && <p className="text-xs text-red-400">{errors.acquisitionDate}</p>}
            {isMulti && <p className="text-2xs text-slate-400 dark:text-zinc-600">Applies to every device. Leave empty to give each device its own date.</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300 min-h-[2.5rem] flex items-start">{isMulti ? 'Total Unit Value (₱)' : 'Unit Value (₱)'}{!isMulti && <span className="text-red-400 ml-0.5">*</span>}</label>
            {isMulti ? (
              <>
                <input readOnly tabIndex={-1} className={INPUT_CLASS + ' bg-slate-50 dark:bg-zinc-800/60 cursor-default'} value={totalUnitValue.toFixed(2)} />
                <p className="text-2xs text-slate-400 dark:text-zinc-600">Sum of every device's unit value below.</p>
              </>
            ) : (
              <input type="number" min="0" step="0.01" className={INPUT_CLASS} placeholder="0.00" value={form.unitValue} onChange={set('unitValue')} />
            )}
            {errors.unitValue && <p className="text-xs text-red-400">{errors.unitValue}</p>}
          </div>
        </div>

        {/* Devices — one Property No. + PAR No. each; every device is its own asset */}
        <div className="flex flex-col gap-2">
          <div className="flex items-baseline justify-between gap-3">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">
              {form.units.length > 1 ? `Devices (${form.units.length})` : 'Property & PAR Number'}<span className="text-red-400 ml-0.5">*</span>
            </label>
            <span className="text-2xs text-slate-400 dark:text-zinc-600 font-mono">
              PAR = {parPrefix(form.acquisitionDate) || 'YYYY-MM'}:SERIAL
            </span>
          </div>
          <p className="text-2xs text-slate-400 dark:text-zinc-600 -mt-1">
            {form.units.length > 1
              ? `Each device is saved as its own asset and shown grouped in the list. Give every device its own Property Number; devices issued together on one PAR share that PAR Number, so type the same serial for each of them. Each device has its own location, accountable person, current user, value, condition, specs and (if no shared date is set) acquisition date; anything under "More details" left blank is copied from this form.${isEditing ? ' Device 1 is the asset you are editing; the others are added as new assets in the same group.' : ''}`
              : 'The Property Number is unique to this asset; the PAR Number is shared by every item issued on the same receipt. The PAR year-month comes from the Acquisition Date; type the serial that follows it.'}
          </p>
          <div className={`space-y-3 ${form.units.length > 3 ? 'max-h-[28rem] overflow-y-auto pr-1' : ''}`}>
            {form.units.map((u, i) => (
              <div key={i} className={form.units.length > 1 ? 'rounded-lg border border-slate-200 dark:border-zinc-700 p-3 space-y-3' : 'space-y-3'}>
                {form.units.length > 1 && (
                  <p className="text-xs font-semibold text-slate-500 dark:text-zinc-400">
                    Device {i + 1} of {form.units.length}{isEditing ? (i === 0 ? ' — this asset' : ' — new') : ''}
                  </p>
                )}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Property Number <span className="text-slate-400 font-normal">(optional)</span></label>
                    <input className={INPUT_CLASS} placeholder="Leave blank to auto-generate" value={u.propertyNumber} onChange={setUnit(i, 'propertyNumber')} />
                  </div>
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">PAR Number<span className="text-red-400 ml-0.5">*</span></label>
                    <div className="flex items-stretch">
                      <span className={`flex items-center rounded-l-md border border-r-0 border-slate-200 dark:border-zinc-700 bg-slate-50 dark:bg-zinc-800/60 px-3 text-sm font-mono ${(u.acquisitionDate || form.acquisitionDate) ? 'text-slate-700 dark:text-zinc-300' : 'text-slate-400 dark:text-zinc-600'}`}>
                        {parPrefix(u.acquisitionDate || form.acquisitionDate) || 'YYYY-MM'}:
                      </span>
                      <input
                        className={INPUT_CLASS + ' rounded-l-none font-mono uppercase'}
                        placeholder="e.g. H78JD80"
                        value={u.parSerial}
                        onChange={setUnit(i, 'parSerial')}
                      />
                    </div>
                  </div>
                </div>
                {errors[`unit${i}`] && <p className="text-xs text-red-400">{errors[`unit${i}`]}</p>}
                {isMulti && (
                  <>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      <div className="flex flex-col gap-1.5">
                        <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Unit Value (₱)<span className="text-red-400 ml-0.5">*</span></label>
                        <input type="number" min="0" step="0.01" className={INPUT_CLASS} placeholder="0.00" value={u.unitValue} onChange={setUnit(i, 'unitValue')} />
                        {errors[`unitv${i}`] && <p className="text-xs text-red-400">{errors[`unitv${i}`]}</p>}
                      </div>
                      <div className="flex flex-col gap-1.5">
                        <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Condition<span className="text-red-400 ml-0.5">*</span></label>
                        <div className="relative">
                          <select className={INPUT_CLASS + ' appearance-none pr-9'} value={u.condition || 'SERVICEABLE'} onChange={setUnit(i, 'condition')}>
                            {CONDITIONS.map((c) => <option key={c} value={c}>{c}</option>)}
                          </select>
                          <ChevronIcon />
                        </div>
                      </div>
                      {!form.acquisitionDate && (
                        <div className="flex flex-col gap-1.5 sm:col-span-2">
                          <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Acquisition Date<span className="text-red-400 ml-0.5">*</span></label>
                          <input type="date" className={INPUT_CLASS} value={u.acquisitionDate} onChange={setUnit(i, 'acquisitionDate')} />
                          {errors[`unitd${i}`] && <p className="text-xs text-red-400">{errors[`unitd${i}`]}</p>}
                        </div>
                      )}
                    </div>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      <div className="flex flex-col gap-1.5">
                        <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Location<span className="text-red-400 ml-0.5">*</span></label>
                        <div className="relative">
                          <select className={INPUT_CLASS + ' appearance-none pr-9' + (staffMode ? ' opacity-60 cursor-not-allowed' : '')} disabled={staffMode} value={u.officeId} onChange={setUnit(i, 'officeId')}>
                            <option value="">Select location</option>
                            {offices.map((o) => <option key={o.id} value={String(o.id)}>{o.officeName}</option>)}
                          </select>
                          <ChevronIcon />
                        </div>
                        {errors[`unito${i}`] && <p className="text-xs text-red-400">{errors[`unito${i}`]}</p>}
                      </div>
                      <div className="flex flex-col gap-1.5">
                        <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Accountable Person<span className="text-red-400 ml-0.5">*</span></label>
                        <div className="relative">
                          <select className={INPUT_CLASS + ' appearance-none pr-9'} value={u.personnelId} onChange={setUnit(i, 'personnelId')}>
                            <option value="">Select accountable person</option>
                            {personnelFor(u.officeId).map((p) => (
                              <option key={p.id} value={String(p.id)}>{p.fullName}{p.position ? ` — ${p.position}` : ''}</option>
                            ))}
                          </select>
                          <ChevronIcon />
                        </div>
                        {errors[`unitp${i}`] && <p className="text-xs text-red-400">{errors[`unitp${i}`]}</p>}
                      </div>
                      <div className="flex flex-col gap-1.5">
                        <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Current User <span className="text-slate-400 font-normal">(optional)</span></label>
                        <div className="relative">
                          <select className={INPUT_CLASS + ' appearance-none pr-9'} value={u.currentUserId} onChange={setUnit(i, 'currentUserId')}>
                            <option value="">Select current user</option>
                            {personnelFor(u.officeId).map((p) => (
                              <option key={p.id} value={String(p.id)}>{p.fullName}{p.position ? ` — ${p.position}` : ''}</option>
                            ))}
                          </select>
                          <ChevronIcon />
                        </div>
                        {errors[`unitc${i}`] && <p className="text-xs text-red-400">{errors[`unitc${i}`]}</p>}
                      </div>
                    </div>
                    <div className="flex flex-col gap-1.5">
                      <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Technical Specifications <span className="text-slate-400 font-normal">(optional)</span></label>
                      <textarea className={INPUT_CLASS + ' resize-none font-mono text-xs'} rows={3}
                        placeholder={'e.g.\nProcessor: Core i7\nMemory: 16 GB\nStorage: 512 GB'}
                        value={u.specifications} onChange={setUnit(i, 'specifications')} />
                    </div>
                    <details>
                      <summary className="cursor-pointer text-xs font-medium text-brand-400 hover:text-brand-300 select-none">
                        More details <span className="text-slate-400 font-normal">(serial number, remarks — blank = same as the form)</span>
                      </summary>
                      <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <div className="flex flex-col gap-1.5">
                          <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Serial Number</label>
                          <input className={INPUT_CLASS} placeholder={form.serialNumber || 'Same as above'} value={u.serialNumber} onChange={setUnit(i, 'serialNumber')} />
                        </div>
                        <div className="flex flex-col gap-1.5">
                          <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Remarks</label>
                          <input className={INPUT_CLASS} placeholder="Same as below" value={u.remarks} onChange={setUnit(i, 'remarks')} />
                        </div>
                      </div>
                    </details>
                  </>
                )}
              </div>
            ))}
          </div>
        </div>

        {/* Location, Accountable Person, Current User — with several devices each device has its own (see Devices above) */}
        {!isMulti && (
        <>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Location<span className="text-red-400 ml-0.5">*</span></label>
            <div className="relative">
              <select className={INPUT_CLASS + ' appearance-none pr-9' + (staffMode ? ' opacity-60 cursor-not-allowed' : '')} disabled={staffMode} title={staffMode ? 'Only an administrator can move an asset to another office' : undefined} value={form.officeId} onChange={set('officeId')}>
                <option value="">— Select location —</option>
                {offices.map((o) => <option key={o.id} value={String(o.id)}>{o.officeName}</option>)}
              </select>
              <ChevronIcon />
            </div>
            {errors.officeId && <p className="text-xs text-red-400">{errors.officeId}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Accountable Person<span className="text-red-400 ml-0.5">*</span></label>
            <div className="relative">
              <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.personnelId} onChange={handlePersonnelChange}>
                <option value="">— Select accountable person —</option>
                {accountableOptions.map((p) => (
                  <option key={p.id} value={String(p.id)}>{p.fullName}{p.position ? ` — ${p.position}` : ''}{p._former ? ' (not an account)' : ''}</option>
                ))}
              </select>
              <ChevronIcon />
            </div>
            {errors.personnelId && <p className="text-xs text-red-400">{errors.personnelId}</p>}
            {form.officeId && personnelForOffice.length === 0 && (
              <p className="text-2xs text-amber-500">No accounts are assigned to this office yet — assign one on the Personnel page.</p>
            )}
          </div>
        </div>

        {/* Current User */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">
            Current User <span className="text-slate-400 font-normal">(optional — who actually has the asset, if different from the accountable person)</span>
          </label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.currentUserId} onChange={set('currentUserId')}>
              <option value="">— Same as accountable person / unspecified —</option>
              {currentUserOptions.map((p) => (
                <option key={p.id} value={String(p.id)}>{p.fullName}{p.position ? ` — ${p.position}` : ''}{p._former ? ' (not an account)' : ''}</option>
              ))}
            </select>
            <ChevronIcon />
          </div>
        </div>
        </>
        )}

        {/* Condition — with several devices each device has its own (see Devices above) */}
        {!isMulti && (
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Condition<span className="text-red-400 ml-0.5">*</span></label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.condition} onChange={set('condition')}>
              {CONDITIONS.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
            <ChevronIcon />
          </div>
        </div>
        )}

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

        {/* Technical Specifications — with several devices each device has its own */}
        {!isMulti && (
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Technical Specifications <span className="text-slate-400 font-normal">(optional)</span></label>
          <textarea
            className={INPUT_CLASS + ' resize-none font-mono text-xs'}
            rows={6}
            placeholder={'e.g.\nProcessor: Core i7\nMemory: 16 GB\nStorage: 512 GB\nDisplay: 15.6" Full HD 1920 x 1080'}
            value={form.specifications}
            onChange={set('specifications')}
          />
          <p className="text-2xs text-slate-400 dark:text-zinc-600">
            Free-form — enter whatever specs apply to this device type (processor/memory/storage for a computer, engine/plate no. for a vehicle, etc.), one per line. Auto-filled by Scan Label/Upload Image when available.
          </p>
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
    </>
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
