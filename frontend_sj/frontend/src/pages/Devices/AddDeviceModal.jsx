import { useState } from 'react'
import { useSelector } from 'react-redux'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import DatePicker from '../../components/common/DatePicker'

const INITIAL_FORM = {
  model:           '',
  serialNumber:    '',
  amountValue:     '',
  acquisitionDate: '',
}

// ── Shared field wrapper ───────────────────────────────────────────────────────
function Field({ label, required, error, children }) {
  return (
    <div className="flex flex-col gap-1.5">
      <label className="text-sm font-medium text-zinc-300">
        {label}{required && <span className="text-red-400 ml-0.5">*</span>}
      </label>
      {children}
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
}

function TextInput({ error, ...props }) {
  return (
    <input
      className={`w-full rounded-md border px-3.5 py-2.5 text-sm bg-zinc-800 text-white placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150 ${
        error ? 'border-red-500' : 'border-zinc-700 hover:border-zinc-600'
      }`}
      {...props}
    />
  )
}

// ── Main component ─────────────────────────────────────────────────────────────
// Add mode:  pass nothing extra        → 2-step flow (select equip → fill form)
// Edit mode: pass initialDevice + inventoryItem → skip to step 2 pre-filled
function AddDeviceModal({ onClose, onSave, initialDevice = null, inventoryItem = null }) {
  const isEditing      = initialDevice !== null
  const inventoryItems = useSelector((s) => s.inventory.items)

  const [step, setStep]             = useState(isEditing ? 2 : 1)
  const [equipSearch, setEquipSearch] = useState('')
  const [selectedEquip, setSelectedEquip] = useState(isEditing ? inventoryItem : null)

  const [form, setForm] = useState(
    isEditing
      ? {
          model:           initialDevice.model           ?? '',
          serialNumber:    initialDevice.serialNumber    ?? '',
          amountValue:     initialDevice.amountValue != null ? String(initialDevice.amountValue) : '',
          acquisitionDate: initialDevice.acquisitionDate ?? '',
        }
      : INITIAL_FORM
  )
  const [errors, setErrors]   = useState({})
  const [saving, setSaving]   = useState(false)

  const set = (key) => (e) => setForm((p) => ({ ...p, [key]: e.target.value }))
  const clearError = (key) => setErrors((p) => { const n = { ...p }; delete n[key]; return n })

  // ── Step 1 filter ────────────────────────────────────────────────────────────
  const filteredEquip = inventoryItems.filter((item) => {
    if (!equipSearch.trim()) return true
    const q = equipSearch.toLowerCase()
    return ['article', 'equipmentType', 'itemCode', 'office', 'location'].some(
      (k) => String(item[k] ?? '').toLowerCase().includes(q)
    )
  })

  const handleSelectEquip = (item) => { setSelectedEquip(item); setStep(2) }

  // ── Validation ───────────────────────────────────────────────────────────────
  const validate = () => {
    const errs = {}
    if (!form.model.trim())        errs.model        = 'Model is required.'
    if (!form.serialNumber.trim()) errs.serialNumber = 'Serial Number is required.'
    return errs
  }

  // ── Submit ───────────────────────────────────────────────────────────────────
  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = validate()
    if (Object.keys(errs).length) { setErrors(errs); return }

    setSaving(true)
    await onSave({
      inventoryId: selectedEquip.id,
      device: isEditing
        ? { ...initialDevice, ...form, amountValue: form.amountValue ? Number(form.amountValue) : 0 }
        : { ...form, amountValue: form.amountValue ? Number(form.amountValue) : 0 },
    })
    setSaving(false)
    onClose()
  }

  // ── Render ───────────────────────────────────────────────────────────────────
  return (
    <Modal
      title={isEditing ? 'Edit Device' : 'Add Device'}
      subtitle={
        step === 1
          ? 'Step 1 of 2 — Select the equipment this device belongs to'
          : isEditing
            ? `Editing device in "${selectedEquip?.article || selectedEquip?.itemCode}"`
            : `Step 2 of 2 — Enter device details for "${selectedEquip?.article || selectedEquip?.itemCode}"`
      }
      onClose={onClose}
      size="xl"
    >
      {/* ── STEP 1: Select equipment ────────────────────────────────────────── */}
      {step === 1 && (
        <div className="space-y-4">
          <div className="relative">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
            </svg>
            <input
              type="text"
              placeholder="Search equipment by article, item code, office…"
              value={equipSearch}
              onChange={(e) => setEquipSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2.5 text-sm rounded-lg border border-zinc-700 bg-zinc-800 text-zinc-200 placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all duration-150"
              autoFocus
            />
          </div>

          {inventoryItems.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 gap-3 text-zinc-600">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
              </svg>
              <div className="text-center">
                <p className="text-sm font-medium text-zinc-500">No inventory records found</p>
                <p className="text-xs text-zinc-600 mt-1">Add equipment in the Inventory module first.</p>
              </div>
            </div>
          ) : filteredEquip.length === 0 ? (
            <p className="text-sm text-zinc-500 text-center py-8">No equipment matches your search.</p>
          ) : (
            <div className="overflow-x-auto rounded-lg border border-zinc-800 max-h-72 overflow-y-auto">
              <table className="min-w-full text-sm divide-y divide-zinc-800">
                <thead className="bg-zinc-900 sticky top-0">
                  <tr>
                    {['Type of Equipment', 'Item Code', 'Article', 'Office', 'Devices'].map((h) => (
                      <th key={h} className="px-4 py-3 text-left text-2xs font-semibold text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="bg-zinc-950 divide-y divide-zinc-800/60">
                  {filteredEquip.map((item) => (
                    <tr key={item.id} onClick={() => handleSelectEquip(item)} className="cursor-pointer hover:bg-zinc-800 transition-colors duration-100">
                      <td className="px-4 py-3 text-zinc-300 whitespace-nowrap">{item.equipmentType || '—'}</td>
                      <td className="px-4 py-3 text-zinc-400 font-mono text-xs whitespace-nowrap">{item.itemCode || '—'}</td>
                      <td className="px-4 py-3 text-white font-medium whitespace-nowrap">{item.article || '—'}</td>
                      <td className="px-4 py-3 text-zinc-400 whitespace-nowrap">{item.office || '—'}</td>
                      <td className="px-4 py-3 whitespace-nowrap">
                        <span className="inline-flex items-center gap-1 text-xs text-zinc-500">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                            <path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" />
                          </svg>
                          {item.deviceCount ?? 0}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <div className="flex justify-end pt-1">
            <Button variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          </div>
        </div>
      )}

      {/* ── STEP 2: Device details ───────────────────────────────────────────── */}
      {step === 2 && (
        <form onSubmit={handleSubmit} noValidate>
          {/* Selected equipment banner */}
          <div className="flex items-start gap-3 p-3.5 bg-zinc-800 rounded-lg border border-zinc-700 mb-5">
            <div className="w-9 h-9 rounded-lg bg-brand-500/20 flex items-center justify-center flex-shrink-0 mt-px">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-brand-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" />
              </svg>
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold text-white truncate">{selectedEquip?.article || '—'}</p>
              <p className="text-xs text-zinc-500 mt-px">
                {[selectedEquip?.equipmentType, selectedEquip?.itemCode, selectedEquip?.office].filter(Boolean).join(' · ')}
              </p>
            </div>
            {/* Device count badge */}
            {(() => {
              const count = selectedEquip?.deviceCount ?? 0
              return (
                <span className={`flex-shrink-0 inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold ${
                  count === 0
                    ? 'bg-zinc-800 text-zinc-500 ring-1 ring-zinc-700'
                    : 'bg-brand-500/10 text-brand-400 ring-1 ring-brand-500/20'
                }`}>
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" />
                  </svg>
                  {count} {count === 1 ? 'device' : 'devices'}
                </span>
              )
            })()}
            {!isEditing && (
              <button
                type="button"
                onClick={() => { setStep(1); setForm(INITIAL_FORM); setErrors({}) }}
                className="ml-auto text-xs text-zinc-500 hover:text-zinc-300 transition-colors whitespace-nowrap"
              >
                Change
              </button>
            )}
          </div>

          <div className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <Field label="Model" required error={errors.model}>
                <TextInput
                  placeholder="e.g. Latitude 5420"
                  value={form.model}
                  onChange={set('model')}
                  onFocus={() => clearError('model')}
                  error={errors.model}
                />
              </Field>
              <Field label="Serial Number" required error={errors.serialNumber}>
                <TextInput
                  placeholder="e.g. SN-ABC123"
                  value={form.serialNumber}
                  onChange={set('serialNumber')}
                  onFocus={() => clearError('serialNumber')}
                  error={errors.serialNumber}
                />
              </Field>
              <Field label="Device Count">
                <div className="w-full rounded-md border border-zinc-700 bg-zinc-800/40 px-3.5 py-2.5 text-sm flex items-center gap-2 cursor-default select-none">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-zinc-500 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" />
                  </svg>
                  <span className="font-semibold text-zinc-200">{selectedEquip?.deviceCount ?? 0}</span>
                  <span className="text-zinc-500">{(selectedEquip?.deviceCount ?? 0) === 1 ? 'device' : 'devices'}</span>
                </div>
              </Field>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <Field label="Amount Value">
                <div className="relative">
                  <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-sm text-zinc-500 pointer-events-none select-none">₱</span>
                  <input
                    type="number" min="0" step="0.01" placeholder="0.00"
                    value={form.amountValue} onChange={set('amountValue')}
                    className="w-full rounded-md border border-zinc-700 pl-7 pr-3.5 py-2.5 text-sm bg-zinc-800 text-white placeholder:text-zinc-600 hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150"
                  />
                </div>
              </Field>
              <Field label="Acquisition Date">
                <DatePicker
                  value={form.acquisitionDate} onChange={set('acquisitionDate')}
                  className="w-full rounded-md border border-zinc-700 px-3.5 py-2.5 text-sm bg-zinc-800 text-white hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150"
                />
              </Field>
            </div>
          </div>

          <div className="flex items-center justify-between mt-6 pt-4 border-t border-zinc-800">
            {!isEditing ? (
              <button
                type="button"
                onClick={() => { setStep(1); setErrors({}) }}
                className="flex items-center gap-1.5 text-sm text-zinc-500 hover:text-zinc-300 transition-colors duration-150"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clipRule="evenodd" />
                </svg>
                Back
              </button>
            ) : <span />}

            <div className="flex gap-2">
              <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
              <Button type="submit" size="md" disabled={saving}>
                {saving ? (
                  <span className="flex items-center gap-2">
                    <svg className="animate-spin h-3.5 w-3.5" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                    </svg>
                    Saving…
                  </span>
                ) : (
                  <span className="flex items-center gap-1.5">
                    {isEditing ? (
                      <>
                        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                          <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                        </svg>
                        Update Device
                      </>
                    ) : (
                      <>
                        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                          <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
                        </svg>
                        Add Device
                      </>
                    )}
                  </span>
                )}
              </Button>
            </div>
          </div>
        </form>
      )}
    </Modal>
  )
}

export default AddDeviceModal
