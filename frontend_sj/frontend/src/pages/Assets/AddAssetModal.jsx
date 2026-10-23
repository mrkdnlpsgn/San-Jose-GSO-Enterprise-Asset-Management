import { useState, useRef } from 'react'
import { inOffice } from '../../services/personnelService'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import CameraCaptureModal from '../../components/common/CameraCaptureModal'
import { createCategory } from '../../services/categoryService'
import { scanAssetLabel } from '../../services/assetService'
import { useToast } from '../../context/ToastContext'
import { newIdempotencyKey } from '../../utils/idempotency'
import { useFormDraft } from '../../hooks/useFormDraft'
import DraftNotice from '../../components/common/DraftNotice'
import DatePicker from '../../components/common/DatePicker'

const PREDEFINED_CATEGORIES = ['Appliances', 'Vehicle', 'Office Supplies']
// The status (Assigned / Under maintenance / Disposed) isn't edited here: it follows the
// condition (Repairable starts maintenance, Unserviceable starts disposal) and the Transfer page.
const CONDITIONS  = [['SERVICEABLE', 'Serviceable'], ['REPAIRABLE', 'Repairable (needs repair)'], ['UNSERVICEABLE', 'Unserviceable (for disposal)']]
const PAR_SERIAL_RE = /^[A-Za-z0-9-]+$/

// PAR number = acquisition year-month + ':' + a serial typed by hand,
// e.g. "2026-07:H78JD80". The prefix is derived from the Acquisition Date field
// rather than typed, so the two can never disagree.
const parPrefix = (acquisitionDate) => (acquisitionDate ? acquisitionDate.slice(0, 7) : '')

const INPUT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

// Every asset is exactly one physical item - Qty (Property Card) and Qty (Physical
// Count) are always 1 and can't be changed. Property Number, PAR Number, and (if
// given) Serial Number must each be unique across every other asset - the backend
// enforces this and returns a friendly message if one collides.
//
// staffMode: a STAFF account editing an asset of its office - it can't move the asset to
// another office or create categories (all admin-only).
export default function AddAssetModal({ onClose, onSave, initial = null, categories = [], offices = [], personnel = [], onCategoryCreated, staffMode = false }) {
  const isEditing = !!initial
  // Required for new assets. Older assets were registered without a PAR / accountable person;
  // editing one shouldn't force inventing them first.
  const parRequired    = !isEditing || !!initial.parNumber
  const personRequired = !isEditing || !!initial.accountablePerson
  const toast = useToast()
  const uploadInputRef = useRef(null)
  // Phones/tablets: a capture input hands off to the device's own camera app, which is
  // full-screen and familiar - far easier for older staff than an in-page webcam preview.
  // Desktops have no camera app, so they keep CameraCaptureModal.
  const cameraInputRef = useRef(null)
  // The form is long: a problem can sit far above or below the button, so after a failed save
  // the first one is scrolled into view (and the button repeats it), or the click looks dead.
  const formRef = useRef(null)
  const showFirstError = () => requestAnimationFrame(() =>
    formRef.current?.querySelector('[data-form-error], p.field-error')?.scrollIntoView({ behavior: 'smooth', block: 'center' }))
  const [scanning, setScanning] = useState(false)
  const [wasScanned, setWasScanned] = useState(false)
  const [showCamera, setShowCamera] = useState(false)

  const [form, setForm] = useState({
    propertyNumber:   initial?.propertyNumber        || '',
    parSerial:        initial?.parNumber?.includes(':') ? initial.parNumber.split(':').slice(1).join(':') : '',
    serialNumber:     initial?.serialNumber          || '',
    description:      initial?.description           || '',
    categoryId:       initial?.category?.id          ? String(initial.category.id) : '',
    acquisitionDate:  initial?.acquisitionDate        || '',
    unitValue:        initial?.unitValue              ?? '',
    officeId:         initial?.office?.id             ? String(initial.office.id) : '',
    personnelId:      initial?.accountablePerson?.id  ? String(initial.accountablePerson.id) : '',
    currentUserId:    initial?.currentUser?.id        ? String(initial.currentUser.id) : '',
    shortageOverageQty:   initial?.shortageOverageQty != null ? String(initial.shortageOverageQty) : '0',
    shortageOverageValue: initial?.shortageOverageValue != null ? String(initial.shortageOverageValue) : '0',
    location:         initial?.location               || '',
    condition:        initial?.condition              || 'SERVICEABLE',
    specifications:   initial?.specifications         || '',
    remarks:          initial?.remarks                || '',
  })
  const draft = useFormDraft(`asset:${initial?.id ?? 'new'}`, form, setForm, {
    title: (f) => isEditing ? `${initial.propertyNumber || 'Asset'}: ${f.description || initial.description || ''}` : (f.description.trim() || 'Untitled asset'),
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

  // deactivated accounts can't take on assets (an asset already assigned to one still shows it - see keepSelected)
  const activePersonnel = personnel.filter((p) => p.userActive !== false)
  // Accountable Person lists only the chosen location's people (the person is custodially
  // tied to that office), and nobody until a location is picked. Current User is who
  // actually has the device right now, which can be anyone active - including someone from
  // another office, or the admin - so it's never office-filtered.
  const personnelForOffice = form.officeId
    ? activePersonnel.filter((p) => inOffice(p, form.officeId))
    : []

  const keepSelected = (list, person) =>
    person && !list.some((p) => p.id === person.id) ? [...list, { ...person, _former: true }] : list
  // The asset's existing accountable person stays listed (e.g. a since-deactivated account) only
  // while the asset stays in its office; pick another office and only that office's people show.
  const inOriginalOffice = String(form.officeId) === String(initial?.office?.id ?? '')
  const accountableOptions = inOriginalOffice
    ? keepSelected(personnelForOffice, initial?.accountablePerson)
    : personnelForOffice
  const currentUserOptions = keepSelected(activePersonnel, initial?.currentUser)

  // A new office drops an accountable person who isn't in it (they're tied to their office).
  const handleOfficeChange = (e) => {
    const officeId = e.target.value
    setForm((p) => {
      const stays = activePersonnel.some((x) => String(x.id) === String(p.personnelId) && inOffice(x, officeId))
        || (String(officeId) === String(initial?.office?.id ?? '') && String(p.personnelId) === String(initial?.accountablePerson?.id ?? ''))
      return { ...p, officeId, personnelId: stays ? p.personnelId : '' }
    })
    setErrors((p) => { const n = { ...p }; delete n.officeId; return n })
  }

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
      toast.show('Scanned. Review the details below.', 'success')
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

  const openCamera = () => {
    if (window.matchMedia?.('(pointer: coarse)').matches) cameraInputRef.current?.click()
    else setShowCamera(true)
  }

  const handleCameraCapture = (file) => {
    setShowCamera(false)
    scanFile(file)
  }

  const validate = () => {
    const e = {}
    if (!form.description.trim())      e.description      = 'Description is required.'
    if (!form.categoryId)              e.categoryId       = 'Category is required.'
    if (!form.officeId)                e.officeId         = 'Office is required.'
    if (!form.personnelId && personRequired) e.personnelId = 'Accountable person is required.'
    if (!form.acquisitionDate)         e.acquisitionDate  = 'Acquisition date is required.'
    if (!form.unitValue && form.unitValue !== 0) e.unitValue = 'Unit value is required.'

    const par = form.parSerial.trim()
    if (!par && !parRequired)         { /* an older asset that never had a PAR may stay without one */ }
    else if (!form.acquisitionDate)   e.parSerial = 'Pick the Acquisition Date first. The PAR Number starts with its year-month.'
    else if (!par)                    e.parSerial = 'PAR serial is required.'
    else if (!PAR_SERIAL_RE.test(par)) e.parSerial = 'PAR serial: letters, numbers, and hyphens only.'
    return e
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = validate()
    if (Object.keys(errs).length) { setErrors(errs); showFirstError(); return }
    setSaving(true)
    try {
      // Resolve category ID - predefined-only entries need to be created first
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
        parNumber:         form.parSerial.trim() ? `${parPrefix(form.acquisitionDate)}:${form.parSerial.trim()}` : '',
        serialNumber:      form.serialNumber.trim() || null,
        description:       form.description.trim(),
        categoryId:        resolvedCategoryId,
        quantity:          1,
        physicalCount:     1,
        acquisitionDate:   form.acquisitionDate || null,
        unitValue:         Number(form.unitValue),
        officeId:          Number(form.officeId),
        personnelId:       form.personnelId ? Number(form.personnelId) : null,
        currentUserId:     form.currentUserId ? Number(form.currentUserId) : null,
        shortageOverageQty:   form.shortageOverageQty !== '' ? Number(form.shortageOverageQty) : 0,
        shortageOverageValue: form.shortageOverageValue !== '' ? Number(form.shortageOverageValue) : 0,
        // the room typed below; just the office name when none is given
        location:          form.location.trim() || selectedOfficeName,
        condition:         form.condition,
        specifications:    form.specifications.trim() || null,
        remarks:           form.remarks.trim() || null,
      }
      await onSave(payload, idempotencyKey, wasScanned)
      draft.clear()
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save asset.' })
      showFirstError()
    } finally {
      setSaving(false)
    }
  }

  const conditionChanged = !isEditing || form.condition !== initial.condition
  const conditionNote = !conditionChanged ? null
    : form.condition === 'REPAIRABLE'
    ? { color: 'amber', text: staffMode
        ? 'A maintenance request will be sent to an administrator. The asset keeps its current condition and status until approved.'
        : 'A maintenance ledger record will be automatically created.' }
    : form.condition === 'UNSERVICEABLE'
    ? { color: 'red',   text: staffMode
        ? 'A disposal request will be sent to an administrator. The asset keeps its current condition and status until approved.'
        : 'A disposal ledger record will be automatically created.' }
    : null


  return (
    <>
    {showCamera && (
      <CameraCaptureModal onCapture={handleCameraCapture} onClose={() => setShowCamera(false)} />
    )}
    <Modal title={isEditing ? 'Edit Asset' : 'Add Asset'} size="lg" onClose={onClose}>
      <form ref={formRef} onSubmit={handleSubmit} noValidate className="space-y-4">
        <DraftNotice draft={draft} />
        {errors._global && (
          <div data-form-error role="alert" className="text-sm text-red-700 dark:text-red-300 bg-red-500/10 border border-red-500/30 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}

        {!isEditing && (
          <section
            aria-labelledby="autofill-heading"
            className="rounded-lg border-2 border-brand-500/60 bg-brand-50 dark:bg-brand-500/10 p-4"
          >
            <input
              ref={uploadInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
              className="hidden"
              onChange={handleUploadChange}
            />
            <input
              ref={cameraInputRef}
              type="file"
              accept="image/*"
              capture="environment"
              className="hidden"
              onChange={handleUploadChange}
            />
            <div className="flex items-start gap-3 mb-3">
              <span className="shrink-0 flex h-9 w-9 items-center justify-center rounded-full bg-brand-600 text-white" aria-hidden="true">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 7V5a1 1 0 011-1h2M17 4h2a1 1 0 011 1v2M20 17v2a1 1 0 01-1 1h-2M7 20H5a1 1 0 01-1-1v-2M8 9h8M8 12h8M8 15h5" />
                </svg>
              </span>
              <div>
                <h3 id="autofill-heading" className="text-sm font-semibold text-slate-900 dark:text-white">
                  Auto-fill from a photo. No typing needed
                </h3>
                <p className="text-xs text-slate-600 dark:text-zinc-300 mt-0.5 leading-relaxed">
                  Take a photo of the device label/sticker or the PAR document. The system reads the
                  description, serial number, and specifications and fills them in for you to review.
                </p>
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              <button
                type="button"
                disabled={scanning}
                onClick={openCamera}
                className="flex items-center justify-center gap-2 rounded-md bg-brand-600 hover:bg-brand-700 text-white px-4 py-3 text-sm font-semibold shadow-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-zinc-900 transition-colors duration-150 disabled:opacity-60 disabled:cursor-not-allowed"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className={`h-5 w-5 ${scanning ? 'animate-pulse' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 17a4 4 0 100-8 4 4 0 000 8z" />
                </svg>
                {scanning ? 'Reading photo…' : 'Take Photo'}
              </button>
              <button
                type="button"
                disabled={scanning}
                onClick={() => uploadInputRef.current?.click()}
                className="flex items-center justify-center gap-2 rounded-md border-2 border-brand-600 bg-white dark:bg-zinc-900 text-brand-700 dark:text-brand-400 hover:bg-brand-50 dark:hover:bg-zinc-800 px-4 py-2.5 text-sm font-semibold focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-zinc-900 transition-colors duration-150 disabled:opacity-60 disabled:cursor-not-allowed"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className={`h-5 w-5 ${scanning ? 'animate-pulse' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 8.25L12 3.75m0 0L7.5 8.25M12 3.75v12.75" />
                </svg>
                {scanning ? 'Reading photo…' : 'Upload Image'}
              </button>
            </div>

            {wasScanned && !scanning ? (
              <p className="flex items-center gap-1.5 text-xs font-medium text-brand-700 dark:text-brand-400 mt-3" role="status">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                  <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                </svg>
                Fields filled in from your photo. Please check them below before saving.
              </p>
            ) : (
              <p className="text-xs text-slate-500 dark:text-zinc-400 mt-3">
                Or skip this and type the details below.
              </p>
            )}
          </section>
        )}

        {/* Serial No. */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">
            Serial Number <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span>
          </label>
          <input className={INPUT_CLASS} placeholder="Manufacturer serial number" value={form.serialNumber} onChange={set('serialNumber')} />
        </div>

        {/* Category */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Category<span className="text-red-600 dark:text-red-400 ml-0.5">*</span></label>
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
                {customError && <p className="field-error text-xs text-red-700 dark:text-red-300">{customError}</p>}
              </div>
            ) : (
              <div className="relative">
                <select
                  className={INPUT_CLASS + ' appearance-none pr-9'}
                  value={form.categoryId}
                  onChange={handleCategoryChange}
                >
                  <option value="">Select category</option>
                  {allCategories.map((c) => (
                    <option key={c.id} value={String(c.id)}>{c.categoryName}</option>
                  ))}
                  {!staffMode && <option value="__custom__">＋ Add custom category…</option>}
                </select>
                <ChevronIcon />
              </div>
            )}
          {errors.categoryId && !customMode && <p className="field-error text-xs text-red-700 dark:text-red-300">{errors.categoryId}</p>}
        </div>

        {/* Description */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Description<span className="text-red-600 dark:text-red-400 ml-0.5">*</span></label>
          <input className={INPUT_CLASS} placeholder="Article / equipment description" value={form.description} onChange={set('description')} />
          {errors.description && <p className="field-error text-xs text-red-700 dark:text-red-300">{errors.description}</p>}
        </div>

        {/* Acq Date + Unit Value. Qty (Property Card) and Physical Count are always 1 - each asset
            is one item, so they aren't asked for. */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Acquisition Date<span className="text-red-600 dark:text-red-400 ml-0.5">*</span></label>
            <DatePicker required className={INPUT_CLASS} value={form.acquisitionDate} onChange={set('acquisitionDate')} />
            {errors.acquisitionDate && <p className="field-error text-xs text-red-700 dark:text-red-300">{errors.acquisitionDate}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Unit Value (₱)<span className="text-red-600 dark:text-red-400 ml-0.5">*</span></label>
            <input type="number" min="0" step="0.01" className={INPUT_CLASS} placeholder="0.00" value={form.unitValue} onChange={set('unitValue')} />
            {errors.unitValue && <p className="field-error text-xs text-red-700 dark:text-red-300">{errors.unitValue}</p>}
          </div>
        </div>

        {/* Shortage/Overage - optional, defaults to 0. Independent of Qty/Physical Count
            (both fixed at 1); a positive number is overage, negative is shortage. */}
        <details className="rounded-lg border border-slate-200 dark:border-zinc-700 px-4 py-3" open={Number(form.shortageOverageQty) !== 0 || Number(form.shortageOverageValue) !== 0}>
          <summary className="cursor-pointer text-sm font-medium text-slate-700 dark:text-zinc-300">Physical count adjustments <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional. Only if the count found a shortage or overage)</span></summary>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-3">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Shortage/Overage Qty <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
            <input type="number" step="1" className={INPUT_CLASS} placeholder="0" value={form.shortageOverageQty} onChange={set('shortageOverageQty')} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Shortage/Overage Value (₱) <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
            <input type="number" step="0.01" className={INPUT_CLASS} placeholder="0.00" value={form.shortageOverageValue} onChange={set('shortageOverageValue')} />
          </div>
        </div>
        <p className="text-xs text-slate-600 dark:text-zinc-400 mt-2">Negative = shortage, positive = overage.</p>
        </details>

        {/* Property & PAR Number */}
        <div className="flex flex-col gap-2">
          <div className="flex items-baseline justify-between gap-3">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Property & PAR Number{parRequired && <span className="text-red-600 dark:text-red-400 ml-0.5">*</span>}</label>
            <span className="text-xs text-slate-600 dark:text-zinc-400 font-mono">
              PAR = {parPrefix(form.acquisitionDate) || 'YYYY-MM'}:SERIAL
            </span>
          </div>
          <p className="text-xs text-slate-600 dark:text-zinc-400 -mt-1">
            The Property Number is unique to this asset (leave blank to auto-generate); the PAR Number's serial
            is also unique to this asset. The PAR year-month comes from the Acquisition Date above.
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Property Number <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
              <input className={INPUT_CLASS} placeholder="Leave blank to auto-generate" value={form.propertyNumber} onChange={set('propertyNumber')} />
            </div>
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">PAR Number{parRequired ? <span className="text-red-600 dark:text-red-400 ml-0.5">*</span> : <span className="font-normal"> (optional. This asset has none yet)</span>}</label>
              <div className="flex items-stretch">
                <span className={`flex items-center whitespace-nowrap rounded-l-md border border-r-0 border-slate-200 dark:border-zinc-700 bg-slate-50 dark:bg-zinc-800/60 px-3 text-sm font-mono ${form.acquisitionDate ? 'text-slate-700 dark:text-zinc-300' : 'text-slate-600 dark:text-zinc-400'}`}>
                  {parPrefix(form.acquisitionDate) || 'YYYY-MM'}:
                </span>
                <input
                  className={INPUT_CLASS + ' rounded-l-none font-mono uppercase'}
                  placeholder="e.g. H78JD80"
                  value={form.parSerial}
                  onChange={set('parSerial')}
                />
              </div>
            </div>
          </div>
          {errors.parSerial && <p className="field-error text-xs text-red-700 dark:text-red-300">{errors.parSerial}</p>}
        </div>

        {/* Location, Accountable Person, Current User */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Office<span className="text-red-600 dark:text-red-400 ml-0.5">*</span></label>
            {staffMode ? (
              <>
                <div className={INPUT_CLASS + ' bg-slate-50 dark:bg-zinc-800/60 cursor-default'}>
                  {offices.find((o) => String(o.id) === String(form.officeId))?.officeName || 'N/A'}
                </div>
                <p className="text-xs text-slate-600 dark:text-zinc-400">Automatically set to your assigned office. Only an administrator can move an asset.</p>
              </>
            ) : (
              <div className="relative">
                <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.officeId} onChange={handleOfficeChange}>
                  <option value="">Select office</option>
                  {offices.map((o) => <option key={o.id} value={String(o.id)}>{o.officeName}</option>)}
                </select>
                <ChevronIcon />
              </div>
            )}
            {errors.officeId && <p className="field-error text-xs text-red-700 dark:text-red-300">{errors.officeId}</p>}
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Accountable Person{personRequired && <span className="text-red-600 dark:text-red-400 ml-0.5">*</span>}</label>
            {staffMode ? (
              // the accountable person decides who can see the asset, so staff can't change it
              <>
                <div className={INPUT_CLASS + ' bg-slate-50 dark:bg-zinc-800/60 cursor-default'}>
                  {initial?.accountablePerson?.fullName || 'N/A'}
                </div>
                <p className="text-xs text-slate-600 dark:text-zinc-400">You are this asset&apos;s accountable person.</p>
              </>
            ) : (
              <div className="relative">
                <select className={INPUT_CLASS + ' appearance-none pr-9 disabled:opacity-60 disabled:cursor-not-allowed'} value={form.personnelId} onChange={handlePersonnelChange} disabled={!form.officeId}>
                  <option value="">{form.officeId ? 'Select accountable person' : 'Select an office first'}</option>
                  {accountableOptions.map((p) => (
                    <option key={p.id} value={String(p.id)}>{p.fullName}{p.position ? `: ${p.position}` : ''}{p._former ? ' (inactive)' : ''}</option>
                  ))}
                </select>
                <ChevronIcon />
              </div>
            )}
            {errors.personnelId && <p className="field-error text-xs text-red-700 dark:text-red-300">{errors.personnelId}</p>}
            {!staffMode && form.officeId && personnelForOffice.length === 0 && (
              <p className="text-xs text-amber-800 dark:text-amber-300">No accounts are assigned to this office yet. Assign one on the Personnel page.</p>
            )}
          </div>
        </div>

        {/* Room / physical location inside the office */}
        <div className="flex flex-col gap-1.5">
          <label htmlFor="asset-location" className="text-sm font-medium text-slate-700 dark:text-zinc-300">
            Room / Location <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span>
          </label>
          <input id="asset-location" className={INPUT_CLASS} placeholder="e.g. Records Section, 2nd floor" value={form.location} onChange={set('location')} />
        </div>

        {/* Current User */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">
            Current User <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional, who actually has the asset, if different from the accountable person; can be anyone, from any office)</span>
          </label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.currentUserId} onChange={set('currentUserId')}>
              <option value="">Same as accountable person / unspecified</option>
              {currentUserOptions.map((p) => (
                <option key={p.id} value={String(p.id)}>{p.fullName}{p.position ? `: ${p.position}` : ''}{p._former ? ' (inactive)' : ''}</option>
              ))}
            </select>
            <ChevronIcon />
          </div>
        </div>

        {/* Condition */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Condition<span className="text-red-600 dark:text-red-400 ml-0.5">*</span></label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.condition} onChange={set('condition')}>
              {CONDITIONS.map(([c, label]) => <option key={c} value={c}>{label}</option>)}
            </select>
            <ChevronIcon />
          </div>
        </div>

        {conditionNote && (
          <div className={`flex items-start gap-2.5 px-4 py-3 rounded-lg border ${
            conditionNote.color === 'amber'
              ? 'bg-amber-500/10 border-amber-500/30 text-amber-800 dark:text-amber-300'
              : 'bg-red-500/10 border-red-500/30 text-red-700 dark:text-red-300'
          }`}>
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 flex-shrink-0 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
            </svg>
            <p className="text-xs font-medium">{conditionNote.text}</p>
          </div>
        )}

        {/* Technical Specifications */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Technical Specifications <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
          <textarea
            className={INPUT_CLASS + ' resize-none font-mono text-xs'}
            rows={6}
            placeholder={'e.g.\nProcessor: Core i7\nMemory: 16 GB\nStorage: 512 GB\nDisplay: 15.6" Full HD 1920 x 1080'}
            value={form.specifications}
            onChange={set('specifications')}
          />
          <p className="text-xs text-slate-600 dark:text-zinc-400">
            Free-form. Enter whatever specs apply to this device type (processor/memory/storage for a computer, engine/plate no. for a vehicle, etc.), one per line. Auto-filled by Take Photo/Upload Image when available.
          </p>
        </div>

        {/* Remarks */}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Remarks <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
          <textarea className={INPUT_CLASS + ' resize-none'} rows={2} placeholder="Additional notes…" value={form.remarks} onChange={set('remarks')} />
        </div>

        <div className="flex justify-end items-center gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          {Object.keys(errors).length > 0 && (
            <p className="mr-auto text-xs text-red-700 dark:text-red-300" role="alert">
              {errors._global || (Object.keys(errors).length === 1
                ? 'Fix the highlighted field above.'
                : `Fix the ${Object.keys(errors).length} highlighted fields above.`)}
            </p>
          )}
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
