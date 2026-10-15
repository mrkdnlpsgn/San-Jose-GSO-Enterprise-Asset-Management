import { useEffect, useRef, useState, useCallback } from 'react'
import { useSelector, useDispatch } from 'react-redux'
import { useNavigate } from 'react-router-dom'
import { Html5Qrcode } from 'html5-qrcode'
import { QRCodeSVG } from 'qrcode.react'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import QrScannerOverlay from '../../components/common/QrScannerOverlay'
import { printQrSticker } from '../../utils/printQrSticker'
import { useToast } from '../../context/ToastContext'
import { getAssets, updateAssetStatus } from '../../services/assetService'
import { getOffices } from '../../services/officeService'
import { getPersonnel } from '../../services/personnelService'
import { getTransfers, submitTransfer, approveTransfer, rejectTransfer } from '../../services/transferService'
import { setAssets, updateAsset as updateAssetInStore } from '../../store/slices/assetSlice'

// Find an asset by its QR code (or Property/PAR Number), then transfer it to another
// office / accountable person / location. An admin's transfer applies at once; a staff
// member's goes to an admin for approval. Update Status and Print QR stay available.

const LIVE_READER_ID = 'qr-reader-viewport'

// Staff can't set TRANSFERRED here (that's what the transfer form is for), and putting an
// asset under maintenance or disposing of it is sent to an admin as a request on save.
const REQUEST_FOR_STATUS = { UNDER_MAINTENANCE: 'maintenance', DISPOSED: 'disposal' }
const DISPOSABLE_CONDITIONS = ['REPAIRABLE', 'UNSERVICEABLE']

const CONDITION_BADGE = {
  SERVICEABLE:   'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 ring-1 ring-emerald-500/20',
  REPAIRABLE:    'bg-amber-500/10 text-amber-700 dark:text-amber-400 ring-1 ring-amber-500/20',
  UNSERVICEABLE: 'bg-red-500/10 text-red-700 dark:text-red-400 ring-1 ring-red-500/20',
}
const LIFECYCLE_BADGE = {
  REGISTERED:       'bg-blue-500/10 text-blue-700 dark:text-blue-400 ring-1 ring-blue-500/20',
  ASSIGNED:         'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 ring-1 ring-emerald-500/20',
  TRANSFERRED:      'bg-orange-500/10 text-orange-700 dark:text-orange-400 ring-1 ring-orange-500/20',
  UNDER_MAINTENANCE:'bg-amber-500/10 text-amber-700 dark:text-amber-400 ring-1 ring-amber-500/20',
  DISPOSED:         'bg-red-500/10 text-red-700 dark:text-red-400 ring-1 ring-red-500/20',
  ARCHIVED:         'bg-zinc-500/10 text-zinc-600 dark:text-zinc-400 ring-1 ring-zinc-500/20',
}
const REQUEST_BADGE = {
  PENDING_APPROVAL: 'bg-amber-500/10 text-amber-700 dark:text-amber-400 ring-1 ring-amber-500/20',
  APPROVED:         'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 ring-1 ring-emerald-500/20',
  REJECTED:         'bg-red-500/10 text-red-700 dark:text-red-400 ring-1 ring-red-500/20',
}

const INPUT = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3.5 py-2.5 text-sm text-slate-800 dark:text-zinc-100 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'
const LABEL = 'block text-sm font-medium text-slate-700 dark:text-zinc-300 mb-1.5'
const CARD = 'bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800'

function fmt(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}
function fmtDateTime(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleString('en-PH', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
}
function php(v) {
  if (v == null) return '—'
  return '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 })
}
const isTouchDevice = () => window.matchMedia?.('(pointer: coarse)').matches

function printAssetQR(asset) {
  const svgEl = document.getElementById('qr-result-svg')
  if (!svgEl) return
  printQrSticker({ qrHtml: svgEl.outerHTML, propertyNumber: asset.propertyNumber, description: asset.description })
}

function TransferAsset() {
  const assetItems = useSelector((s) => s.assets.items)
  const dispatch   = useDispatch()
  const navigate   = useNavigate()
  const { show }   = useToast()
  const isAdmin    = useSelector((s) => s.auth.user?.role === 'ADMIN')

  const [offices, setOffices]       = useState([])
  const [personnel, setPersonnel]   = useState([])
  const [requests, setRequests]     = useState([])

  useEffect(() => {
    if (assetItems.length === 0) {
      getAssets().then(({ data }) => dispatch(setAssets(data))).catch(() => {})
    }
    getOffices().then(({ data }) => setOffices(data || [])).catch(() => {})
    getPersonnel().then(({ data }) => setPersonnel(data || [])).catch(() => {})
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const loadRequests = useCallback(() => {
    getTransfers(isAdmin ? 'PENDING_APPROVAL' : undefined)
      .then(({ data }) => setRequests(data || []))
      .catch(() => {})
  }, [isAdmin])
  useEffect(() => { loadRequests() }, [loadRequests])

  // ── Finding the asset ──────────────────────────────────────────────────────
  const [scanning, setScanning]       = useState(false)
  const [starting, setStarting]       = useState(false)
  const [phoneScan, setPhoneScan]     = useState(false)
  const [cameraError, setCameraError] = useState('')
  const [result, setResult]           = useState(null)
  const [notFound, setNotFound]       = useState(false)
  const [manualCode, setManualCode]   = useState('')

  const liveScannerRef = useRef(null)
  const isRunning      = useRef(false)
  const resultRef      = useRef(null)

  const stopScanner = useCallback(async () => {
    if (liveScannerRef.current && isRunning.current) {
      try { await liveScannerRef.current.stop() } catch {}
      isRunning.current = false
      setScanning(false)
    }
  }, [])

  useEffect(() => () => { stopScanner() }, [stopScanner])

  const processCode = useCallback((raw) => {
    const code = raw.trim()
    if (!code) return

    // Accepts the app's QR payload format `asset:{id}:{propertyNumber}`, a bare
    // numeric id, a bare property number, or a PAR Number like `2026-07:H78JD80`
    // (manual entry).
    let id = code
    let propertyNumber = code
    let parNumber = code.toLowerCase()
    if (code.startsWith('asset:')) {
      const parts = code.split(':')
      id = parts[1] || ''
      propertyNumber = parts[2] || ''
      parNumber = null
    }

    const asset = assetItems.find(
      (a) =>
        String(a.id) === id ||
        a.propertyNumber?.toLowerCase() === propertyNumber.toLowerCase() ||
        (parNumber && a.parNumber?.toLowerCase() === parNumber)
    )
    if (asset) { setResult(asset); setNotFound(false) }
    else        { setNotFound(true); setResult(null) }
    // On phones the result sits below the search card — bring it into view.
    if (window.matchMedia?.('(max-width: 1023px)').matches) {
      setTimeout(() => resultRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 50)
    }
  }, [assetItems])

  // Phones/tablets: full-screen live scanner with a guide square. Desktops: the inline
  // webcam scanner.
  const startScan = () => {
    setCameraError('')
    setResult(null)
    setNotFound(false)
    if (isTouchDevice()) setPhoneScan(true)
    else startLiveScanner()
  }

  const handlePhoneScan = useCallback((text) => {
    setPhoneScan(false)
    processCode(text)
  }, [processCode])
  const closePhoneScan = useCallback(() => setPhoneScan(false), [])

  const startLiveScanner = async () => {
    setStarting(true)
    try {
      const devices = await Html5Qrcode.getCameras()
      if (!devices || devices.length === 0) {
        setCameraError('No camera detected on this device. Type the Property Number below instead.')
        return
      }
      const camera = devices.find((d) => /back|rear|environment/i.test(d.label)) || devices[0]
      if (!liveScannerRef.current) liveScannerRef.current = new Html5Qrcode(LIVE_READER_ID)
      await liveScannerRef.current.start(
        camera.id,
        { fps: 10, qrbox: { width: 240, height: 240 } },
        async (text) => { await stopScanner(); processCode(text) },
        () => {}
      )
      isRunning.current = true
      setScanning(true)
    } catch (err) {
      const raw  = typeof err === 'string' ? err : (err?.message || err?.name || JSON.stringify(err) || '')
      const low  = raw.toLowerCase()
      let reason = `Camera error: ${raw || 'unknown'}`
      if (low.includes('permission') || low.includes('denied') || low.includes('notallowed'))
        reason = 'Camera permission denied. Click the camera icon in the address bar, allow access, then try again.'
      else if (low.includes('not found') || low.includes('notfound') || low.includes('no camera'))
        reason = 'No camera detected on this device. Type the Property Number below instead.'
      else if (low.includes('in use') || low.includes('notreadable') || low.includes('already'))
        reason = 'Camera is in use by another app or tab. Close it and try again.'
      setCameraError(reason)
    } finally {
      setStarting(false)
    }
  }

  const handleManualSearch = (e) => {
    e.preventDefault()
    if (!manualCode.trim()) return
    processCode(manualCode)
  }

  const handleClear = () => {
    setResult(null)
    setNotFound(false)
    setManualCode('')
    setEditingStatus(false)
    setCameraError('')
  }

  const applyAssetUpdate = (asset) => {
    setResult(asset)
    dispatch(updateAssetInStore(asset))
  }

  // ── Transfer form ──────────────────────────────────────────────────────────
  const [transfer, setTransfer]         = useState({ toOfficeId: '', toPersonnelId: '', toLocation: '', reason: '' })
  const [transferErrors, setTransferErrors] = useState({})
  const [submitting, setSubmitting]     = useState(false)
  const pendingForResult = result && requests.find((r) => r.assetId === result.id && r.status === 'PENDING_APPROVAL')

  useEffect(() => {
    setTransfer({ toOfficeId: '', toPersonnelId: '', toLocation: '', reason: '' })
    setTransferErrors({})
  }, [result?.id])

  const setT = (key) => (e) => {
    const value = e.target.value
    setTransfer((p) => ({ ...p, [key]: value, ...(key === 'toOfficeId' ? { toPersonnelId: '' } : {}) }))
    setTransferErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const officePersonnel = personnel.filter((p) => String(p.office?.id) === String(transfer.toOfficeId))

  const submitTransferForm = async (e) => {
    e.preventDefault()
    const errs = {}
    if (!transfer.toOfficeId) errs.toOfficeId = 'Choose the office the asset is moving to.'
    if (!transfer.toLocation.trim()) errs.toLocation = 'Enter where the asset will be kept.'
    setTransferErrors(errs)
    if (Object.keys(errs).length) return

    setSubmitting(true)
    try {
      const { data } = await submitTransfer({
        assetId: result.id,
        toOfficeId: Number(transfer.toOfficeId),
        toPersonnelId: transfer.toPersonnelId ? Number(transfer.toPersonnelId) : null,
        toLocation: transfer.toLocation.trim(),
        reason: transfer.reason.trim() || null,
      })
      if (data.status === 'APPLIED') {
        applyAssetUpdate(data.asset)
        show(`Asset transferred to ${data.asset.office?.officeName || 'the new office'}.`, 'success')
      } else {
        show('Transfer request sent — an administrator needs to approve it.', 'success')
      }
      setTransfer({ toOfficeId: '', toPersonnelId: '', toLocation: '', reason: '' })
      loadRequests()
    } catch (err) {
      show(err.response?.data?.message || 'Failed to transfer the asset.', 'error')
    } finally {
      setSubmitting(false)
    }
  }

  // ── Admin: approve / reject staff requests ─────────────────────────────────
  const [rejectingId, setRejectingId] = useState(null)
  const [rejectNote, setRejectNote]   = useState('')
  const [reviewingId, setReviewingId] = useState(null)

  const approve = async (r) => {
    setReviewingId(r.id)
    try {
      const { data } = await approveTransfer(r.id)
      dispatch(updateAssetInStore(data))
      if (result?.id === data.id) setResult(data)
      show(`Approved — ${r.propertyNumber} moved to ${r.toOfficeName}.`, 'success')
      loadRequests()
    } catch (err) {
      show(err.response?.data?.message || 'Failed to approve the request.', 'error')
    } finally {
      setReviewingId(null)
    }
  }

  const reject = async (r) => {
    setReviewingId(r.id)
    try {
      await rejectTransfer(r.id, rejectNote)
      show(`Rejected the transfer of ${r.propertyNumber}.`, 'success')
      setRejectingId(null)
      setRejectNote('')
      loadRequests()
    } catch (err) {
      show(err.response?.data?.message || 'Failed to reject the request.', 'error')
    } finally {
      setReviewingId(null)
    }
  }

  // ── Update Status (kept from the old QR Scanner) ───────────────────────────
  const [editingStatus, setEditingStatus] = useState(false)
  const [statusForm, setStatusForm]   = useState({ condition: '', lifecycleStatus: '' })
  const [savingStatus, setSavingStatus] = useState(false)
  const [statusHint, setStatusHint]   = useState('')

  const startEditStatus = () => {
    setStatusForm({ condition: result.condition, lifecycleStatus: result.lifecycleStatus })
    setEditingStatus(true)
  }
  const cancelEditStatus = () => { setEditingStatus(false); setStatusHint('') }

  const handleLifecycleChange = (e) => {
    const value = e.target.value
    setStatusHint('')
    setStatusForm((p) => ({ ...p, lifecycleStatus: value }))
    const kind = !isAdmin && value !== result.lifecycleStatus ? REQUEST_FOR_STATUS[value] : null
    if (kind) {
      setStatusHint(`Saving sends a ${kind} request to an administrator — the asset stays ${result.lifecycleStatus.replace('_', ' ')} until it's approved.`)
    }
  }

  // REGISTERED / ARCHIVED are never set by the system, so they aren't offered.
  const lifecycleOptions = ['ASSIGNED', 'TRANSFERRED', 'UNDER_MAINTENANCE', 'DISPOSED'].filter(
    (s) => isAdmin || s !== 'TRANSFERRED' || result?.lifecycleStatus === 'TRANSFERRED')

  const saveStatus = async () => {
    if (!isAdmin && statusForm.lifecycleStatus === 'DISPOSED' && statusForm.lifecycleStatus !== result.lifecycleStatus
        && !DISPOSABLE_CONDITIONS.includes(statusForm.condition)) {
      setStatusHint('Only assets marked REPAIRABLE or UNSERVICEABLE can be disposed — set the condition first.')
      return
    }
    setSavingStatus(true)
    try {
      const { data } = await updateAssetStatus(result.id, statusForm.condition, statusForm.lifecycleStatus)
      applyAssetUpdate(data)
      setEditingStatus(false)
      setStatusHint('')
      show(data.pendingRequest
        ? `${data.pendingRequest === 'MAINTENANCE' ? 'Maintenance' : 'Disposal'} request sent — an administrator needs to approve it.`
        : 'Asset status updated.', 'success')
    } catch (err) {
      show(err.response?.data?.message || 'Failed to update status.', 'error')
    } finally {
      setSavingStatus(false)
    }
  }

  const qrValue = result ? `asset:${result.id}:${result.propertyNumber}` : ''
  const busy = scanning || starting

  return (
    <MainLayout>
      {phoneScan && <QrScannerOverlay onDetected={handlePhoneScan} onClose={closePhoneScan} />}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 items-start">

        {/* Find the asset — on phones the found asset comes right after this, then the requests */}
        <div className="lg:col-start-1 lg:row-start-1">
          <section className={`${CARD} overflow-hidden`} aria-label="Find an asset">
            <div className="p-5 space-y-4">
              {/* Live webcam viewport (desktops). Phones use the full-screen scanner. */}
              <div className={scanning || starting ? 'rounded-lg overflow-hidden bg-slate-100 dark:bg-zinc-950' : 'hidden'}>
                <div id={LIVE_READER_ID} className="w-full" />
              </div>

              {scanning ? (
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                    <p className="text-sm text-slate-600 dark:text-zinc-300">Point the camera at the QR code…</p>
                  </div>
                  <Button variant="secondary" size="sm" onClick={stopScanner}>Stop</Button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={startScan}
                  disabled={busy}
                  className="w-full flex items-center justify-center gap-2.5 rounded-lg bg-brand-600 hover:bg-brand-700 text-white px-4 py-4 text-base font-semibold shadow-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-zinc-900 transition-colors duration-150 disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                    <path fillRule="evenodd" d="M3 4a1 1 0 011-1h3a1 1 0 011 1v3a1 1 0 01-1 1H4a1 1 0 01-1-1V4zm2 2V5h1v1H5zM3 13a1 1 0 011-1h3a1 1 0 011 1v3a1 1 0 01-1 1H4a1 1 0 01-1-1v-3zm2 2v-1h1v1H5zM13 3a1 1 0 00-1 1v3a1 1 0 001 1h3a1 1 0 001-1V4a1 1 0 00-1-1h-3zm1 2v1h1V5h-1zM11 7a1 1 0 112 0v1h1a1 1 0 110 2h-2a1 1 0 01-1-1V7zM7 11a1 1 0 100 2h1v1a1 1 0 102 0v-2a1 1 0 00-1-1H7zM13 11a1 1 0 100 2h.01a1 1 0 100-2H13zM15 13a1 1 0 100 2h.01a1 1 0 100-2H15zM13 15a1 1 0 100 2h.01a1 1 0 100-2H13z" clipRule="evenodd" />
                  </svg>
                  Scan QR Code
                </button>
              )}

              {cameraError && (
                <p className="text-sm text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-900 rounded-md px-3.5 py-2.5" role="alert">
                  {cameraError}
                </p>
              )}

              <div className="flex items-center gap-3" aria-hidden="true">
                <span className="h-px flex-1 bg-slate-200 dark:bg-zinc-800" />
                <span className="text-xs text-slate-400 dark:text-zinc-500">or</span>
                <span className="h-px flex-1 bg-slate-200 dark:bg-zinc-800" />
              </div>

              <form onSubmit={handleManualSearch} className="flex gap-2">
                <label htmlFor="manual-code" className="sr-only">Property Number or PAR Number</label>
                <div className="relative flex-1">
                  <svg xmlns="http://www.w3.org/2000/svg" className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 dark:text-zinc-500" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                    <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
                  </svg>
                  <input
                    id="manual-code"
                    type="search"
                    placeholder="Search asset"
                    value={manualCode}
                    onChange={(e) => setManualCode(e.target.value)}
                    className={`${INPUT} pl-9`}
                  />
                </div>
                <Button type="submit" size="md">Search</Button>
              </form>
            </div>
          </section>
        </div>

        {/* ── Right: the asset, transfer form, status tools ─────────────────── */}
        <div ref={resultRef} className="space-y-4 lg:col-start-2 lg:row-start-1 lg:row-span-2 scroll-mt-20">
          {!result && !notFound && (
            <div className={`${CARD} flex flex-col items-center justify-center gap-3 p-8 min-h-[320px]`}>
              <div className="w-16 h-16 rounded-2xl bg-slate-100 dark:bg-zinc-800 flex items-center justify-center">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-8 w-8 text-slate-400 dark:text-zinc-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
                </svg>
              </div>
              <p className="text-sm text-slate-500 dark:text-zinc-400 text-center max-w-xs">
                Scan or search for an asset.
              </p>
            </div>
          )}

          {notFound && (
            <div className={`${CARD} border-red-200 dark:border-red-800/40 p-8 flex flex-col items-center justify-center gap-3 min-h-[320px] animate-fade-slide`}>
              <p className="text-base font-semibold text-red-600 dark:text-red-400">Asset not found</p>
              <p className="text-sm text-slate-500 dark:text-zinc-400 text-center">
                No asset matches this code{isAdmin ? '' : ' in your office'}. Check the Property Number and try again.
              </p>
              <Button variant="secondary" size="sm" onClick={handleClear}>Clear</Button>
            </div>
          )}

          {result && (
            <>
              {/* Asset summary */}
              <div className={`${CARD} overflow-hidden animate-fade-slide`}>
                <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-2 flex-wrap">
                  <div className="flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full bg-emerald-500" />
                    <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Asset found</p>
                  </div>
                  <div className="flex items-center gap-3">
                    <button onClick={() => navigate('/asset-history')} className="text-xs font-semibold text-slate-500 dark:text-zinc-400 hover:text-slate-800 dark:hover:text-zinc-200 transition-colors">History</button>
                    <button onClick={() => printAssetQR(result)} className="text-xs font-semibold text-brand-600 dark:text-brand-400 hover:text-brand-700 dark:hover:text-brand-300 transition-colors">Print QR</button>
                    <button onClick={handleClear} className="text-xs text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-300 transition-colors">Clear</button>
                  </div>
                </div>

                <div className="p-5 space-y-4">
                  <div className="flex items-start gap-4">
                    <div className="bg-white p-2 rounded-lg ring-1 ring-slate-200 dark:ring-zinc-700 shrink-0">
                      <QRCodeSVG id="qr-result-svg" value={qrValue} size={84} bgColor="#ffffff" fgColor="#111827" level="H" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-base font-semibold text-slate-900 dark:text-white leading-snug">{result.description}</p>
                      <p className="text-sm font-mono text-slate-500 dark:text-zinc-400 mt-0.5">{result.propertyNumber}</p>
                      <div className="flex items-center gap-2 flex-wrap mt-2">
                        <span className={`inline-flex px-2.5 py-1 rounded-full text-xs font-semibold ${CONDITION_BADGE[result.condition] || ''}`}>{result.condition}</span>
                        <span className={`inline-flex px-2.5 py-1 rounded-full text-xs font-semibold ${LIFECYCLE_BADGE[result.lifecycleStatus] || ''}`}>{result.lifecycleStatus?.replace('_', ' ')}</span>
                      </div>
                    </div>
                  </div>

                  <div className="rounded-lg bg-slate-50 dark:bg-zinc-950 border border-slate-200 dark:border-zinc-800 px-4 py-3 grid grid-cols-1 sm:grid-cols-3 gap-3">
                    {[
                      ['Current office', result.office?.officeName],
                      ['Location', result.location],
                      ['Accountable', result.accountablePerson?.fullName],
                    ].map(([label, value]) => (
                      <div key={label}>
                        <p className="text-2xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider">{label}</p>
                        <p className="text-sm text-slate-800 dark:text-zinc-100 mt-0.5">{value || '—'}</p>
                      </div>
                    ))}
                  </div>
                </div>
              </div>

              {/* Transfer */}
              <section className={`${CARD} border-2 border-brand-500/50 overflow-hidden`} aria-labelledby="transfer-heading">
                <div className="px-5 py-4 border-b border-slate-200 dark:border-zinc-800 bg-brand-50 dark:bg-brand-500/10">
                  <h2 id="transfer-heading" className="text-base font-semibold text-slate-800 dark:text-zinc-100">Transfer this asset</h2>
                  <p className="text-sm text-slate-600 dark:text-zinc-300 mt-0.5">
                    {isAdmin
                      ? 'The transfer takes effect as soon as you save it.'
                      : 'Your transfer is sent to an administrator. The asset stays where it is until it is approved.'}
                  </p>
                </div>

                {pendingForResult && !isAdmin ? (
                  <p className="px-5 py-5 text-sm text-amber-700 dark:text-amber-400">
                    A transfer of this asset to <strong>{pendingForResult.toOfficeName}</strong> is already waiting for approval.
                  </p>
                ) : (
                  <form onSubmit={submitTransferForm} noValidate className="p-5 space-y-4">
                    <div>
                      <label htmlFor="to-office" className={LABEL}>Move to office<span className="text-red-500 ml-0.5">*</span></label>
                      <select id="to-office" value={transfer.toOfficeId} onChange={setT('toOfficeId')} className={INPUT}>
                        <option value="">— Select office —</option>
                        {offices.map((o) => (
                          <option key={o.id} value={o.id}>{o.officeName}{o.id === result.office?.id ? ' (current)' : ''}</option>
                        ))}
                      </select>
                      {transferErrors.toOfficeId && <p className="text-xs text-red-500 mt-1">{transferErrors.toOfficeId}</p>}
                    </div>

                    <div>
                      <label htmlFor="to-location" className={LABEL}>New location<span className="text-red-500 ml-0.5">*</span></label>
                      <input id="to-location" value={transfer.toLocation} onChange={setT('toLocation')} placeholder="e.g. Room 204, 2nd Floor" maxLength={150} className={INPUT} />
                      {transferErrors.toLocation && <p className="text-xs text-red-500 mt-1">{transferErrors.toLocation}</p>}
                    </div>

                    <div>
                      <label htmlFor="to-person" className={LABEL}>New accountable person <span className="text-slate-400 font-normal">(optional)</span></label>
                      <select id="to-person" value={transfer.toPersonnelId} onChange={setT('toPersonnelId')} disabled={!transfer.toOfficeId} className={`${INPUT} disabled:opacity-60`}>
                        <option value="">{transfer.toOfficeId ? '— None —' : '— Choose the office first —'}</option>
                        {officePersonnel.map((p) => <option key={p.id} value={p.id}>{p.fullName}</option>)}
                      </select>
                      {transfer.toOfficeId && officePersonnel.length === 0 && (
                        <p className="text-xs text-slate-500 dark:text-zinc-400 mt-1">No staff are assigned to this office yet.</p>
                      )}
                    </div>

                    <div>
                      <label htmlFor="to-reason" className={LABEL}>Reason <span className="text-slate-400 font-normal">(optional)</span></label>
                      <textarea id="to-reason" value={transfer.reason} onChange={setT('reason')} rows={2} maxLength={500} placeholder="e.g. Reassigned to the new Records Officer" className={INPUT} />
                    </div>

                    <div className="flex justify-end">
                      <Button type="submit" size="md" disabled={submitting}>
                        {submitting ? 'Saving…' : isAdmin ? 'Transfer Asset' : 'Send Transfer Request'}
                      </Button>
                    </div>
                  </form>
                )}
              </section>

              {/* Update Status (as on the old QR Scanner) */}
              <div className={`${CARD} p-5`}>
                {editingStatus ? (
                  <div className="space-y-3">
                    <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Update status</p>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      <label className="block">
                        <span className="text-2xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider">Condition</span>
                        <select value={statusForm.condition} onChange={(e) => setStatusForm((p) => ({ ...p, condition: e.target.value }))} className={`mt-1 ${INPUT}`}>
                          {Object.keys(CONDITION_BADGE).map((c) => <option key={c} value={c}>{c}</option>)}
                        </select>
                      </label>
                      <label className="block">
                        <span className="text-2xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider">Lifecycle Status</span>
                        <select value={statusForm.lifecycleStatus} onChange={handleLifecycleChange} className={`mt-1 ${INPUT}`}>
                          {lifecycleOptions.map((s) => (
                            <option key={s} value={s} disabled={!isAdmin && s === 'TRANSFERRED'}>
                              {s.replace('_', ' ')}{!isAdmin && REQUEST_FOR_STATUS[s] && s !== result.lifecycleStatus ? ' (needs approval)' : ''}
                            </option>
                          ))}
                        </select>
                      </label>
                    </div>
                    {statusHint && <p className="text-xs text-amber-600 dark:text-amber-400">{statusHint}</p>}
                    <div className="flex items-center gap-2 justify-end">
                      <Button variant="secondary" size="sm" onClick={cancelEditStatus} disabled={savingStatus}>Cancel</Button>
                      <Button size="sm" onClick={saveStatus} disabled={savingStatus}>{savingStatus ? 'Saving…' : 'Save Status'}</Button>
                    </div>
                  </div>
                ) : (
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Condition or status changed?</p>
                      <p className="text-xs text-slate-500 dark:text-zinc-400 mt-0.5">Mark it repairable, under maintenance, and so on.</p>
                    </div>
                    <Button variant="secondary" size="sm" onClick={startEditStatus}>Update Status</Button>
                  </div>
                )}
              </div>

              {/* Other details */}
              <details className={`${CARD} group`}>
                <summary className="px-5 py-3.5 text-sm font-semibold text-slate-700 dark:text-zinc-300 cursor-pointer select-none">More details</summary>
                <div className="px-5 pb-5 grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3">
                  {[
                    { label: 'PAR Number',      value: result.parNumber },
                    { label: 'Serial Number',   value: result.serialNumber },
                    { label: 'Category',        value: result.category?.categoryName },
                    { label: 'Current User',    value: result.currentUser?.fullName },
                    { label: 'Unit Value',      value: php(result.unitValue) },
                    { label: 'Acquisition Date', value: fmt(result.acquisitionDate) },
                    { label: 'Specifications',  value: result.specifications, full: true, multiline: true },
                    { label: 'Remarks',         value: result.remarks, full: true },
                  ].filter((f) => f.value).map(({ label, value, full, multiline }) => (
                    <div key={label} className={full ? 'sm:col-span-2' : ''}>
                      <p className="text-2xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider">{label}</p>
                      <p className={`text-sm text-slate-700 dark:text-zinc-200 mt-0.5 leading-snug ${multiline ? 'whitespace-pre-line' : ''}`}>{value}</p>
                    </div>
                  ))}
                </div>
              </details>
            </>
          )}
        </div>
        <div className="lg:col-start-1 lg:row-start-2">
          {/* Requests: admins review pending staff transfers; staff see their own */}
          <section className={`${CARD} overflow-hidden`} aria-labelledby="requests-heading">
            <div className="px-5 py-4 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
              <div>
                <h2 id="requests-heading" className="text-base font-semibold text-slate-800 dark:text-zinc-100">
                  {isAdmin ? 'Transfer requests to review' : 'My transfer requests'}
                </h2>
                <p className="text-sm text-slate-500 dark:text-zinc-400 mt-0.5">
                  {isAdmin ? 'Transfers filed by staff wait here for your approval.' : 'Transfers you send wait for an administrator to approve them.'}
                </p>
              </div>
              {isAdmin && requests.length > 0 && (
                <span className="shrink-0 inline-flex items-center justify-center min-w-[1.75rem] h-7 px-2 rounded-full bg-amber-500 text-white text-sm font-semibold">{requests.length}</span>
              )}
            </div>
            {requests.length === 0 ? (
              <p className="px-5 py-6 text-sm text-slate-400 dark:text-zinc-500 text-center">
                {isAdmin ? 'No transfer requests waiting.' : "You haven't sent any transfer requests."}
              </p>
            ) : (
              <ul className="divide-y divide-slate-100 dark:divide-zinc-800">
                {requests.map((r) => (
                  <li key={r.id} className="px-5 py-4 space-y-2">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-slate-800 dark:text-zinc-100">
                          <span className="font-mono">{r.propertyNumber}</span> — {r.assetDescription}
                        </p>
                        <p className="text-sm text-slate-600 dark:text-zinc-300 mt-0.5">
                          {r.fromOfficeName || 'Unassigned'} <span aria-hidden="true">→</span><span className="sr-only">to</span> <strong>{r.toOfficeName}</strong> · {r.toLocation}
                          {r.toPersonnelName ? ` · ${r.toPersonnelName}` : ''}
                        </p>
                        {r.reason && <p className="text-xs text-slate-500 dark:text-zinc-400 mt-1">Reason: {r.reason}</p>}
                        <p className="text-xs text-slate-400 dark:text-zinc-500 mt-1">
                          {isAdmin ? `Requested by ${r.requestedByName || 'staff'} · ` : ''}{fmtDateTime(r.requestedAt)}
                        </p>
                        {r.status === 'REJECTED' && r.reviewNote && (
                          <p className="text-xs text-red-600 dark:text-red-400 mt-1">Note from admin: {r.reviewNote}</p>
                        )}
                      </div>
                      {!isAdmin && (
                        <span className={`shrink-0 inline-flex px-2.5 py-1 rounded-full text-xs font-semibold ${REQUEST_BADGE[r.status] || ''}`}>
                          {r.status === 'PENDING_APPROVAL' ? 'Waiting' : r.status === 'APPROVED' ? 'Approved' : 'Rejected'}
                        </span>
                      )}
                    </div>

                    {isAdmin && (rejectingId === r.id ? (
                      <div className="flex flex-col sm:flex-row gap-2">
                        <label htmlFor={`reject-${r.id}`} className="sr-only">Reason for rejecting</label>
                        <input
                          id={`reject-${r.id}`}
                          value={rejectNote}
                          onChange={(e) => setRejectNote(e.target.value)}
                          placeholder="Reason for rejecting (optional)"
                          className={INPUT}
                        />
                        <div className="flex gap-2 shrink-0">
                          <Button variant="secondary" size="sm" onClick={() => { setRejectingId(null); setRejectNote('') }}>Cancel</Button>
                          <Button size="sm" onClick={() => reject(r)} disabled={reviewingId === r.id}>Confirm Reject</Button>
                        </div>
                      </div>
                    ) : (
                      <div className="flex gap-2">
                        <Button size="sm" onClick={() => approve(r)} disabled={reviewingId === r.id}>
                          {reviewingId === r.id ? 'Approving…' : 'Approve'}
                        </Button>
                        <Button variant="secondary" size="sm" onClick={() => setRejectingId(r.id)} disabled={reviewingId === r.id}>Reject</Button>
                      </div>
                    ))}
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </div>
    </MainLayout>
  )
}

export default TransferAsset
