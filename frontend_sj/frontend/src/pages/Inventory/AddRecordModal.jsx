import { useState, useEffect, useCallback, memo } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import { addDevice as addDeviceApi, updateDevice as updateDeviceApi } from '../../services/inventoryService'
import { escapeHtml } from '../../utils/helpers'
import { buildQrValue } from '../../utils/qrUtils'
import { newIdempotencyKey } from '../../utils/idempotency'

const QR_CARD_STYLES = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #fff; }
  .card { border: 2px solid #e5e7eb; border-radius: 16px; padding: 28px 32px; text-align: center; max-width: 300px; width: 100%; }
  .card svg { display: block; margin: 0 auto 16px; }
  .title { font-size: 17px; font-weight: 700; color: #111827; margin-bottom: 4px; }
  .sub   { font-size: 12px; color: #6b7280; margin-bottom: 2px; }
  .sn    { font-size: 11px; font-family: monospace; color: #374151; margin-top: 4px; }
  .badge { display: inline-block; margin-top: 10px; padding: 3px 12px; background: #f3f4f6; border-radius: 999px; font-size: 11px; font-weight: 600; color: #374151; }
  .org   { margin-top: 14px; padding-top: 12px; border-top: 1px solid #f3f4f6; font-size: 10px; color: #9ca3af; }
`

function buildQRCardHTML(equipment, device, svgHTML) {
  const sn   = device?.serialNumber ? `<p class="sn">S/N: ${escapeHtml(device.serialNumber)}</p>` : ''
  const code = escapeHtml(equipment.itemCode)
  const loc  = [equipment.office, equipment.location].filter(Boolean).map(escapeHtml).join(' · ')
  return `<div class="card">
    ${svgHTML}
    <p class="title">${escapeHtml(equipment.article) || '—'}</p>
    <p class="sub">${escapeHtml(equipment.equipmentType) || ''}</p>
    <p class="sub">${loc}</p>
    ${sn}
    <span class="badge">${code}</span>
    <p class="org">San Jose Municipal Hall · GSO Inventory Management System</p>
  </div>`
}

function printDeviceQR(equipment, device, svgId) {
  const svgEl = document.getElementById(svgId)
  if (!svgEl) return
  const win = window.open('', '_blank', 'width=480,height=640')
  win.document.write(`<!DOCTYPE html><html><head>
  <title>QR Code – ${escapeHtml(equipment.article || equipment.itemCode)}</title>
  <style>${QR_CARD_STYLES}
    body { display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 24px; }
  </style></head><body>
  ${buildQRCardHTML(equipment, device, svgEl.outerHTML)}
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
  </body></html>`)
  win.document.close()
}

function printAllDeviceQRs(equipment, devices) {
  const cards = devices.map((device, i) => {
    const svgEl = document.getElementById(`new-item-qr-svg-${i}`)
    return svgEl ? buildQRCardHTML(equipment, device, svgEl.outerHTML) : null
  }).filter(Boolean)
  if (!cards.length) return
  const win = window.open('', '_blank', 'width=900,height=700')
  win.document.write(`<!DOCTYPE html><html><head>
  <title>QR Codes – ${equipment.article || equipment.itemCode}</title>
  <style>${QR_CARD_STYLES}
    body { padding: 20px; }
    h1 { font-size: 13px; font-weight: 700; margin-bottom: 14px; color: #111; }
    .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
    .card { border-width: 1.5px; padding: 14px 12px; break-inside: avoid; }
    .card svg { margin-bottom: 8px; }
    .title { font-size: 12px; }
    .sub, .sn { font-size: 10px; }
    .badge { font-size: 10px; margin-top: 6px; padding: 2px 8px; }
    .org { font-size: 9px; margin-top: 8px; padding-top: 6px; }
    @media print { @page { margin: 10mm; } body { padding: 0; } }
  </style></head><body>
  <h1>GSO Inventory QR Codes — San Jose Municipal Hall (${devices.length} unit${devices.length !== 1 ? 's' : ''})</h1>
  <div class="grid">${cards.join('')}</div>
  <script>window.onload=()=>{window.print();window.onafterprint=()=>window.close()}<\/script>
  </body></html>`)
  win.document.close()
}

// ── Option lists ─────────────────────────────────────────────────────────────
const TYPE_OPTIONS = [
  'Hardware',
  'Software',
  'Peripherals',
  'Network Equipment',
  'Communication Equipment',
  'Other',
]

const EQUIPMENT_OPTIONS = [
  'Desktop Computer',
  'Laptop / Notebook',
  'Tablet',
  'All-in-One Computer',
  'Server',
  'Monitor / Display',
  'Printer',
  'Scanner',
  'Photocopier / MFP',
  'Keyboard',
  'Mouse',
  'UPS',
  'AVR',
  'Router',
  'Network Switch',
  'Wireless Access Point',
  'IP Phone / VoIP',
  'CCTV Camera',
  'Projector',
  'External Storage',
  'Other',
]

const OFFICE_OPTIONS = [
  'Bureau of Fire Protection (BFP)',
  'Department of Education (DepEd)',
  'Department of the Interior and Local Government (DILG)',
  'Local Economic Enterprise Management - Operation of Public Market',
  'Local Economic Enterprise Management - Operation of Waterworks System',
  'Office of the Municipal Accountant',
  'Office of the Municipal Administrator',
  'Office of the Municipal Agriculturist',
  'Office of the Municipal Assessor',
  'Office of the Municipal Budget Officer',
  'Office of the Municipal Civil Registrar',
  'Office of the Municipal Disaster Risk Reduction and Management Section',
  'Office of the Municipal Engineer',
  'Office of the Municipal General Services Officer',
  'Office of the Municipal Health Officer',
  'Office of the Municipal Human Resource Management Officer',
  'Office of the Municipal Information Technology Section',
  'Office of the Municipal Internal Audit Service Officer',
  'Office of the Municipal Mayor',
  'Office of the Municipal Permits And Licensing Section',
  'Office of the Municipal Persons With Disability Affairs Section',
  'Office of the Municipal Planning And Development Coordinator',
  'Office of the Municipal Public Employment Service Manager',
  'Office of the Municipal Social Welfare And Development Officer',
  'Office of the Municipal Tourism Section',
  'Office of the Municipal Treasurer',
  'Office of the Municipal Vice Mayor',
  'Office of the Municipal Youth Development Section',
  'Office of the Secretary To The Sangguniang Bayan',
  'Philippine National Police (PNP)',
  'PILMES',
]

const INITIAL_FORM = {
  type:              '',
  equipmentType:     '',
  itemCode:          '',
  article:           '',
  model:             '',
  serialNumbers:     [''],
  amountValue:       '',
  acquisitionDate:   '',
  deviceCount:       '',
  office:            '',
  location:          '',
  description:       '',
  accountablePerson:      '',
  accountablePersonPhone: '',
  accountablePersonEmail: '',
}

// ── Reusable sub-components ───────────────────────────────────────────────────
const Field = memo(function Field({ label, required, hint, error, children }) {
  return (
    <div className="flex flex-col gap-1.5">
      <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">
        {label}
        {required && <span className="text-red-400 ml-0.5">*</span>}
      </label>
      {children}
      {hint && !error && (
        <p className="text-xs text-slate-400 dark:text-zinc-600 leading-snug">{hint}</p>
      )}
      {error && (
        <p className="flex items-center gap-1 text-xs text-red-400">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
          {error}
        </p>
      )}
    </div>
  )
})

const TextInput = memo(function TextInput({ error, ...props }) {
  return (
    <input
      className={`
        w-full rounded-md border px-3.5 py-2.5 text-sm
        bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600
        focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500
        transition-all duration-150
        ${error ? 'border-red-500' : 'border-slate-200 dark:border-zinc-700 hover:border-slate-300 dark:hover:border-zinc-600'}
      `}
      {...props}
    />
  )
})

const SelectInput = memo(function SelectInput({ options, placeholder, error, ...props }) {
  return (
    <div className="relative">
      <select
        className={`
          w-full appearance-none rounded-md border px-3.5 py-2.5 pr-9 text-sm
          bg-white dark:bg-zinc-800 text-slate-900 dark:text-white
          focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500
          transition-all duration-150
          ${error ? 'border-red-500' : 'border-slate-200 dark:border-zinc-700 hover:border-slate-300 dark:hover:border-zinc-600'}
        `}
        {...props}
      >
        <option value="" disabled>{placeholder}</option>
        {options.map((opt) => (
          <option key={opt} value={opt}>{opt}</option>
        ))}
      </select>
      <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-400">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
        </svg>
      </div>
    </div>
  )
})

// ── Main component ────────────────────────────────────────────────────────────
function AddRecordModal({ onClose, onSave, initialData = null, generatedCode = '', existingSerialNumbers = [], onComplete = null }) {
  const isEditing           = initialData !== null
  const [form, setForm]     = useState(
    initialData
      ? {
          type:              initialData.type              ?? '',
          equipmentType:     initialData.equipmentType     ?? '',
          itemCode:          initialData.itemCode          ?? '',
          article:           initialData.article           ?? '',
          model:             initialData.devices?.[0]?.model             ?? '',
          serialNumbers:     initialData.devices?.length > 0
                               ? initialData.devices.map((d) => d.serialNumber ?? '')
                               : [''],
          amountValue:       initialData.devices?.[0]?.amountValue != null ? String(initialData.devices[0].amountValue) : '',
          acquisitionDate:   initialData.devices?.[0]?.acquisitionDate   ?? '',
          deviceCount:       initialData.deviceCount != null ? String(initialData.deviceCount) : '',
          office:            initialData.office            ?? '',
          location:          initialData.location          ?? '',
          description:       initialData.description       ?? '',
          accountablePerson:      initialData.accountablePerson      ?? '',
          accountablePersonPhone: initialData.accountablePersonPhone ?? '',
          accountablePersonEmail: initialData.accountablePersonEmail ?? '',
        }
      : { ...INITIAL_FORM, itemCode: generatedCode }
  )
  const [errors, setErrors]       = useState({})
  const [saving, setSaving]       = useState(false)
  const [stage, setStage]         = useState('form')  // 'form' | 'qr'
  const [savedItem, setSavedItem] = useState(null)
  const [savedDevices, setSavedDevices] = useState([])
  const [qrTokens, setQrTokens]   = useState({})
  const [idempotencyKey] = useState(() => newIdempotencyKey())

  useEffect(() => {
    if (stage !== 'qr' || !savedItem || savedDevices.length === 0) return
    Promise.all(
      savedDevices.map((device, i) =>
        buildQrValue(savedItem.id, device?.serialNumber || null).then((t) => [i, t])
      )
    ).then((pairs) => setQrTokens(Object.fromEntries(pairs)))
  }, [stage, savedItem, savedDevices])

  const handleChange = useCallback((e) => {
    const { name, value } = e.target
    setForm((prev) => {
      const next = { ...prev, [name]: value }
      if (name === 'deviceCount') {
        const count = Math.max(1, parseInt(value, 10) || 1)
        const cur   = prev.serialNumbers
        next.serialNumbers = count > cur.length
          ? [...cur, ...Array(count - cur.length).fill('')]
          : cur.slice(0, count)
      }
      return next
    })
    setErrors((prev) => { const next = { ...prev }; delete next[name]; return next })
  }, [])

  const handleSerialChange = useCallback((index, value) => {
    setForm((prev) => {
      const serialNumbers = [...prev.serialNumbers]
      serialNumbers[index] = value
      return { ...prev, serialNumbers }
    })
  }, [])

  const clearError = useCallback((key) => {
    setErrors((prev) => { const next = { ...prev }; delete next[key]; return next })
  }, [])

  const clearSerialError = useCallback((index) => {
    setErrors((prev) => {
      if (!prev.serialNumbers?.[index]) return prev
      const sns  = { ...prev.serialNumbers }
      delete sns[index]
      const next = { ...prev }
      if (Object.keys(sns).length === 0) delete next.serialNumbers
      else next.serialNumbers = sns
      return next
    })
  }, [])

  const validate = () => {
    const errs = {}
    if (!form.type)                           errs.type                  = 'Type is required.'
    if (!form.equipmentType)                  errs.equipmentType         = 'Type of Equipment is required.'
    if (!form.article.trim())                 errs.article               = 'Article is required.'
    if (!form.office)                         errs.office                = 'Office is required.'
    if (!form.location.trim())                errs.location              = 'Location is required.'
    if (!form.accountablePerson.trim())       errs.accountablePerson     = 'Accountable Person is required.'
    if (!form.accountablePersonEmail.trim())  errs.accountablePersonEmail = 'Contact Email is required.'
    if (!form.accountablePersonPhone.trim())  errs.accountablePersonPhone = 'Contact Number is required.'

    const lowerExisting = existingSerialNumbers.map((s) => s.toLowerCase())
    const snErrs = {}
    const filled = form.serialNumbers
      .map((s, i) => ({ val: s.trim(), i }))
      .filter((x) => x.val)

    filled.forEach(({ val, i }) => {
      const lower = val.toLowerCase()
      if (lowerExisting.includes(lower)) {
        snErrs[i] = 'Serial number already exists in inventory.'
      } else if (filled.filter((x) => x.val.toLowerCase() === lower).length > 1) {
        snErrs[i] = 'Duplicate serial number within this record.'
      }
    })

    if (Object.keys(snErrs).length) errs.serialNumbers = snErrs
    return errs
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = validate()
    if (Object.keys(errs).length) { setErrors(errs); return }

    setSaving(true)

    const equipmentPayload = {
      type:              form.type,
      equipmentType:     form.equipmentType,
      itemCode:          form.itemCode,
      article:           form.article,
      office:            form.office,
      location:          form.location,
      description:       form.description,
      accountablePerson:      form.accountablePerson,
      accountablePersonPhone: form.accountablePersonPhone || null,
      accountablePersonEmail: form.accountablePersonEmail || null,
      deviceCount:            form.deviceCount ? Number(form.deviceCount) : 0,
    }

    const deviceBase = {
      model:           form.model           || null,
      amountValue:     form.amountValue     ? Number(form.amountValue) : null,
      acquisitionDate: form.acquisitionDate || null,
    }
    const deviceCount      = Number(form.deviceCount) || 0
    const hasDeviceDetails = deviceCount > 0 || form.model || form.serialNumbers.some((s) => s.trim()) || form.amountValue || form.acquisitionDate

    if (isEditing) {
      await onSave({ ...initialData, ...equipmentPayload })
      const existingDevices = initialData.devices || []

      if (existingDevices.length > 0) {
        await Promise.all(
          existingDevices.map((device, i) =>
            updateDeviceApi(initialData.id, device.id, {
              ...deviceBase,
              itemCode:     form.itemCode,
              serialNumber: form.serialNumbers[i]?.trim() || null,
            }).catch(() => {})
          )
        )
      } else if (hasDeviceDetails) {
        await addDeviceApi(initialData.id, {
          ...deviceBase,
          itemCode:     form.itemCode,
          serialNumber: form.serialNumbers[0]?.trim() || null,
        }, `${idempotencyKey}-edit-device`).catch(() => {})
      }
      setSaving(false)
      onClose()
    } else {
      const item = await onSave(equipmentPayload, idempotencyKey)
      if (item) {
        if (hasDeviceDetails) {
          const results = await Promise.all(
            form.serialNumbers.map((sn, i) =>
              addDeviceApi(item.id, {
                ...deviceBase,
                itemCode:     form.itemCode,
                serialNumber: sn.trim() || null,
              }, `${idempotencyKey}-device-${i}`)
                .then((r) => r.data)
                .catch(() => null)
            )
          )
          setSavedDevices(results.filter(Boolean))
        }
        if (onComplete) onComplete()
        setSaving(false)
        setSavedItem(item)
        setStage('qr')
      } else {
        setSaving(false)
        onClose()
      }
    }
  }

  return (
    <Modal
      title={
        stage === 'qr'
          ? 'Equipment Added'
          : isEditing ? 'Edit Inventory Record' : 'Add Inventory Record'
      }
      subtitle={
        stage === 'qr'
          ? savedDevices.length > 1
            ? `${savedDevices.length} QR codes ready — one per device unit`
            : 'Your QR code is ready to print'
          : isEditing
            ? `Editing: ${initialData.article || initialData.itemCode}`
            : 'Fill in the details of the new ICT equipment'
      }
      onClose={onClose}
      size="lg"
    >
      {/* ── QR Code stage ─────────────────────────────────────────────── */}
      {stage === 'qr' && savedItem && (
        <div className="flex flex-col items-center gap-5 py-2">
          {/* Success icon */}
          <div className="w-12 h-12 rounded-full bg-emerald-950 flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 text-emerald-400" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
            </svg>
          </div>

          {savedDevices.length > 1 ? (
            /* ── Multiple devices: grid of QR cards ── */
            <>
              <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">
                {savedDevices.length} QR Codes Generated
              </p>
              <div className="w-full grid grid-cols-2 sm:grid-cols-3 gap-3 max-h-[400px] overflow-y-auto pr-1">
                {savedDevices.map((device, i) => {
                  const svgId = `new-item-qr-svg-${i}`
                  const code  = savedItem.itemCode || ''
                  return (
                    <div key={i} className="bg-slate-50 dark:bg-zinc-800 border border-slate-100 dark:border-zinc-700 rounded-xl p-3 flex flex-col items-center gap-2">
                      <div className="bg-white p-2 rounded-lg">
                        <QRCodeSVG
                          id={svgId}
                          value={qrTokens[i] || '…'}
                          size={96}
                          bgColor="#ffffff"
                          fgColor="#111827"
                          level="H"
                        />
                      </div>
                      <div className="flex flex-col items-center gap-1 text-center w-full">
                        <p className="text-2xs font-semibold text-slate-800 dark:text-zinc-100 leading-tight truncate w-full">
                          {savedItem.article || '—'}
                        </p>
                        {device?.serialNumber && (
                          <span className="text-[0.625rem] font-mono text-slate-500 dark:text-zinc-400 truncate max-w-full">
                            {device.serialNumber}
                          </span>
                        )}
                        <span className="text-[0.625rem] bg-slate-200 dark:bg-zinc-700 text-slate-600 dark:text-zinc-300 px-2 py-0.5 rounded-full font-semibold">
                          {code}
                        </span>
                      </div>
                      <button
                        onClick={() => printDeviceQR(savedItem, device, svgId)}
                        className="flex items-center gap-1 text-[0.625rem] font-semibold text-brand-600 dark:text-brand-400 hover:text-brand-500 transition-colors"
                      >
                        <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                          <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
                        </svg>
                        Print
                      </button>
                    </div>
                  )
                })}
              </div>
              <div className="flex gap-3 w-full pt-1 border-t border-slate-100 dark:border-zinc-800">
                <Button variant="secondary" size="md" className="flex-1" onClick={() => printAllDeviceQRs(savedItem, savedDevices)}>
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
                  </svg>
                  Print All QR Codes
                </Button>
                <Button size="md" className="flex-1" onClick={onClose}>Done</Button>
              </div>
            </>
          ) : (
            /* ── Single device: one large QR card ── */
            <>
              <div className="flex flex-col items-center gap-4 w-full">
                <div className="bg-white p-5 rounded-2xl shadow-lg">
                  <QRCodeSVG
                    id="new-item-qr-svg-0"
                    value={qrTokens[0] || '…'}
                    size={160}
                    bgColor="#ffffff"
                    fgColor="#111827"
                    level="H"
                  />
                </div>
                <div className="space-y-1 text-center">
                  <p className="text-base font-semibold text-slate-900 dark:text-white">{savedItem.article || '—'}</p>
                  <p className="text-xs text-slate-500 dark:text-zinc-500">
                    {[savedItem.equipmentType, savedItem.itemCode, savedItem.office].filter(Boolean).join(' · ')}
                  </p>
                  {savedDevices[0]?.serialNumber && (
                    <p className="text-xs font-mono text-slate-400 dark:text-zinc-400">S/N: {savedDevices[0].serialNumber}</p>
                  )}
                </div>
              </div>
              <div className="flex gap-3 w-full pt-1 border-t border-slate-100 dark:border-zinc-800">
                <Button variant="secondary" size="md" className="flex-1" onClick={() => printDeviceQR(savedItem, savedDevices[0], 'new-item-qr-svg-0')}>
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
                  </svg>
                  Print QR Code
                </Button>
                <Button size="md" className="flex-1" onClick={onClose}>Done</Button>
              </div>
            </>
          )}
        </div>
      )}

      {/* ── Form stage ────────────────────────────────────────────────── */}
      {stage === 'form' && <form onSubmit={handleSubmit} noValidate>
        <div className="space-y-4">

          {/* Section: Classification */}
          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest mb-3">
              Classification
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="Type" required hint="Broad category: Hardware, Software, Network Equipment, etc." error={errors.type}>
                <SelectInput
                  name="type"
                  options={TYPE_OPTIONS}
                  placeholder="Select type…"
                  value={form.type}
                  onChange={handleChange}
                />
              </Field>
              <Field label="Type of Equipment" required hint="The specific device type, e.g. Laptop, Printer, Router." error={errors.equipmentType}>
                <SelectInput
                  name="equipmentType"
                  options={EQUIPMENT_OPTIONS}
                  placeholder="Select equipment…"
                  value={form.equipmentType}
                  onChange={handleChange}
                />
              </Field>
            </div>
          </div>

          <div className="border-t border-slate-200 dark:border-zinc-800" />

          {/* Section: Identification */}
          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest mb-3">
              Identification
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="Item Code" hint="Auto-generated unique identifier.">
                <div className="w-full rounded-md border border-slate-200 dark:border-zinc-700 bg-slate-100 dark:bg-zinc-800/50 px-3.5 py-2.5 text-sm font-mono text-slate-700 dark:text-zinc-300 flex items-center gap-2 select-none">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5 text-slate-400 dark:text-zinc-500 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" />
                  </svg>
                  {form.itemCode || '—'}
                </div>
              </Field>
              <Field label="Article" required hint="Full equipment name as it appears on the property tag or procurement record." error={errors.article}>
                <TextInput
                  name="article"
                  placeholder="e.g. Dell Latitude 5420"
                  value={form.article}
                  onChange={handleChange}
                  onFocus={() => clearError('article')}
                  error={errors.article}
                />
              </Field>
            </div>
          </div>

          <div className="border-t border-slate-200 dark:border-zinc-800" />

          {/* Section: Location */}
          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest mb-3">
              Location
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="Office" required error={errors.office}>
                <SelectInput
                  name="office"
                  options={OFFICE_OPTIONS}
                  placeholder="Select office…"
                  value={form.office}
                  onChange={handleChange}
                />
              </Field>
              <Field label="Location" required error={errors.location}>
                <TextInput
                  name="location"
                  placeholder="e.g. Room 201, 2nd Floor"
                  value={form.location}
                  onChange={handleChange}
                />
              </Field>
            </div>
          </div>

          <div className="border-t border-slate-200 dark:border-zinc-800" />

          {/* Section: Device Details */}
          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest mb-3">
              Device Details
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="Model">
                <TextInput
                  name="model"
                  placeholder="e.g. Latitude 5420"
                  value={form.model}
                  onChange={handleChange}
                />
              </Field>
              <Field
                label="Device Count"
                hint={isEditing ? 'Device count is fixed when editing.' : 'Each unit gets its own serial number field.'}
              >
                <input
                  name="deviceCount"
                  type="number" min="0" step="1" placeholder="0"
                  value={form.deviceCount}
                  onChange={isEditing ? undefined : handleChange}
                  readOnly={isEditing}
                  className={`w-full rounded-md border px-3.5 py-2.5 text-sm text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none transition-all duration-150 ${
                    isEditing
                      ? 'border-slate-200 dark:border-zinc-700 bg-slate-100 dark:bg-zinc-800/50 cursor-not-allowed select-none'
                      : 'border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 hover:border-slate-300 dark:hover:border-zinc-600 focus:ring-2 focus:ring-brand-500 focus:border-brand-500'
                  }`}
                />
              </Field>
              <Field label="Amount Value">
                <div className="relative">
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-sm text-slate-400 dark:text-zinc-500 pointer-events-none select-none">₱</span>
                  <input
                    name="amountValue"
                    type="number" min="0" step="0.01" placeholder="0.00"
                    value={form.amountValue}
                    onChange={handleChange}
                    className="w-full rounded-md border border-slate-200 dark:border-zinc-700 pl-7 pr-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 hover:border-slate-300 dark:hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150"
                  />
                </div>
              </Field>
              <Field label="Acquisition Date">
                <input
                  name="acquisitionDate"
                  type="date"
                  value={form.acquisitionDate}
                  onChange={handleChange}
                  className="w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white hover:border-slate-300 dark:hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150 [color-scheme:light] dark:[color-scheme:dark]"
                />
              </Field>
            </div>

            {/* Serial Numbers — one per device unit */}
            <div className="mt-4">
              {form.serialNumbers.length === 1 ? (
                <Field label="Serial Number" hint="Must be unique across all inventory records." error={errors.serialNumbers?.[0]}>
                  <TextInput
                    placeholder="e.g. SN-ABC123"
                    value={form.serialNumbers[0]}
                    onChange={(e) => handleSerialChange(0, e.target.value)}
                    onFocus={() => clearSerialError(0)}
                    error={errors.serialNumbers?.[0]}
                  />
                </Field>
              ) : (
                <div>
                  <p className="text-sm font-medium text-slate-700 dark:text-zinc-300 mb-2">
                    Serial Numbers
                    <span className="text-slate-400 dark:text-zinc-500 text-xs font-normal ml-1.5">— one per unit, must each be unique</span>
                  </p>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    {form.serialNumbers.map((sn, i) => (
                      <Field key={i} label={`Unit ${i + 1}`} error={errors.serialNumbers?.[i]}>
                        <TextInput
                          placeholder={`Serial number for unit ${i + 1}`}
                          value={sn}
                          onChange={(e) => handleSerialChange(i, e.target.value)}
                          onFocus={() => clearSerialError(i)}
                          error={errors.serialNumbers?.[i]}
                        />
                      </Field>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>

          <div className="border-t border-slate-200 dark:border-zinc-800" />

          {/* Section: Additional Details */}
          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-widest mb-3">
              Additional Details
            </p>
            <div className="space-y-4">
              <Field label="Description">
                <textarea
                  name="description"
                  rows={3}
                  placeholder="Brief description of the equipment, condition, or notes…"
                  value={form.description}
                  onChange={handleChange}
                  className="
                    w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm
                    bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600
                    hover:border-slate-300 dark:hover:border-zinc-600 focus:outline-none focus:ring-2
                    focus:ring-brand-500 focus:border-brand-500
                    transition-all duration-150 resize-none
                  "
                />
              </Field>
              <Field label="Accountable Person" required hint="The staff member officially responsible for this equipment per property records." error={errors.accountablePerson}>
                <TextInput
                  name="accountablePerson"
                  placeholder="e.g. Juan Dela Cruz"
                  value={form.accountablePerson}
                  onChange={handleChange}
                />
              </Field>
              <Field label="Contact Email" required hint="Email address for notifications when this device is checked out or transferred." error={errors.accountablePersonEmail}>
                <TextInput
                  name="accountablePersonEmail"
                  type="email"
                  placeholder="e.g. juan.delacruz@sjmh.gov.ph"
                  value={form.accountablePersonEmail}
                  onChange={handleChange}
                />
              </Field>
              <Field label="Contact Number" required hint="Mobile number for SMS alerts when this device is checked out or transferred." error={errors.accountablePersonPhone}>
                <div className="relative">
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-sm text-slate-400 dark:text-zinc-500 pointer-events-none select-none">+63</span>
                  <input
                    name="accountablePersonPhone"
                    placeholder="9XXXXXXXXX"
                    value={form.accountablePersonPhone}
                    onChange={handleChange}
                    maxLength={10}
                    className="w-full rounded-md border border-slate-200 dark:border-zinc-700 pl-11 pr-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 hover:border-slate-300 dark:hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150"
                  />
                </div>
              </Field>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between mt-6 pt-4 border-t border-slate-200 dark:border-zinc-800">
          <p className="text-xs text-slate-400 dark:text-zinc-600">
            Fields marked <span className="text-red-400">*</span> are required
          </p>
          <div className="flex gap-2">
            <Button type="button" variant="secondary" size="md" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" size="md" disabled={saving}>
              {saving ? (
                <span className="flex items-center gap-2">
                  <svg className="animate-spin h-3.5 w-3.5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                  </svg>
                  Saving…
                </span>
              ) : isEditing ? (
                <span className="flex items-center gap-1.5">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                  </svg>
                  Update Record
                </span>
              ) : (
                <span className="flex items-center gap-1.5">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
                  </svg>
                  Save Record
                </span>
              )}
            </Button>
          </div>
        </div>
      </form>}
    </Modal>
  )
}

export default AddRecordModal
