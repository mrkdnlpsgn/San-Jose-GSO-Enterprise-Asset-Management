import { useEffect, useRef, useState, useCallback } from 'react'
import { useSelector, useDispatch } from 'react-redux'
import { useNavigate } from 'react-router-dom'
import { Html5Qrcode } from 'html5-qrcode'
import { QRCodeSVG } from 'qrcode.react'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import { useToast } from '../../context/ToastContext'
import { getAssets, updateAssetStatus } from '../../services/assetService'
import { setAssets, updateAsset as updateAssetInStore } from '../../store/slices/assetSlice'
import AddMaintenanceModal from '../Maintenance/AddMaintenanceModal'
import AddDisposalModal from '../Disposal/AddDisposalModal'
import { createMaintenance } from '../../services/maintenanceService'
import { createDisposal } from '../../services/disposalService'
import { getUsers } from '../../services/userService'

const READER_ID = 'qr-reader-viewport'

// Staff can't transfer an asset (an admin assigns it), and putting one under maintenance
// or disposing of it goes through a request an admin approves — picking those statuses
// opens the matching request form instead of changing the status directly.
const REQUEST_FOR_STATUS = { UNDER_MAINTENANCE: 'maintenance', DISPOSED: 'disposal' }
const DISPOSABLE_CONDITIONS = ['REPAIRABLE', 'UNSERVICEABLE']

const CONDITION_BADGE = {
  SERVICEABLE:   'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  REPAIRABLE:    'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  UNSERVICEABLE: 'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
}
const LIFECYCLE_BADGE = {
  REGISTERED:       'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  ASSIGNED:         'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  TRANSFERRED:      'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  UNDER_MAINTENANCE:'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  DISPOSED:         'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
  ARCHIVED:         'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20',
}

function fmt(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}
function php(v) {
  if (v == null) return '—'
  return '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 })
}

function printAssetQR(asset) {
  const svgEl = document.getElementById('qr-result-svg')
  if (!svgEl) return
  const svgHTML = svgEl.outerHTML
  const esc = (s) => String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
  const win = window.open('', '_blank', 'width=480,height=640')
  win.document.write(`<!DOCTYPE html>
<html>
<head>
  <title>QR Code – ${esc(asset.propertyNumber)}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', Arial, sans-serif; background: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 24px; }
    .card { border: 2px solid #e5e7eb; border-radius: 16px; padding: 28px 32px; text-align: center; max-width: 300px; width: 100%; }
    .card svg { display: block; margin: 0 auto 16px; }
    .title { font-size: 17px; font-weight: 700; color: #111827; margin-bottom: 4px; }
    .sub   { font-size: 12px; color: #6b7280; margin-bottom: 2px; }
    .badge { display: inline-block; margin-top: 10px; padding: 3px 12px; background: #f3f4f6; border-radius: 999px; font-size: 11px; font-weight: 600; color: #374151; }
    .org   { margin-top: 14px; padding-top: 12px; border-top: 1px solid #f3f4f6; font-size: 10px; color: #9ca3af; }
  </style>
</head>
<body>
  <div class="card">
    ${svgHTML}
    <p class="title">${esc(asset.description)}</p>
    <p class="sub">${esc(asset.category?.categoryName || '')}</p>
    <p class="sub">${esc(asset.office?.officeName || '')}${asset.location ? ' · ' + esc(asset.location) : ''}</p>
    <span class="badge">${esc(asset.propertyNumber)}</span>
    <p class="org">San Jose Municipal Hall · GSO Inventory Management System</p>
  </div>
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
</body>
</html>`)
  win.document.close()
}

function QRScanner() {
  const assetItems = useSelector((s) => s.assets.items)
  const dispatch   = useDispatch()
  const navigate   = useNavigate()
  const { show }   = useToast()
  const isAdmin    = useSelector((s) => s.auth.user?.role === 'ADMIN')

  useEffect(() => {
    if (assetItems.length === 0) {
      getAssets().then(({ data }) => dispatch(setAssets(data))).catch(() => {})
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const [scanning, setScanning]       = useState(false)
  const [cameraError, setCameraError] = useState('')
  const [result, setResult]           = useState(null)
  const [notFound, setNotFound]       = useState(false)
  const [manualCode, setManualCode]   = useState('')
  const [editingStatus, setEditingStatus] = useState(false)
  const [statusForm, setStatusForm]   = useState({ condition: '', lifecycleStatus: '' })
  const [savingStatus, setSavingStatus] = useState(false)
  const [requestKind, setRequestKind] = useState(null)   // 'maintenance' | 'disposal' — staff request form open
  const [statusHint, setStatusHint]   = useState('')
  const [users, setUsers]             = useState([])

  const scannerRef = useRef(null)
  const isRunning  = useRef(false)

  const stopScanner = useCallback(async () => {
    if (scannerRef.current && isRunning.current) {
      try { await scannerRef.current.stop() } catch {}
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
  }, [assetItems])

  const startScanner = async () => {
    setCameraError('')
    setResult(null)
    setNotFound(false)

    try {
      const devices = await Html5Qrcode.getCameras()
      if (!devices || devices.length === 0) {
        setCameraError('No camera detected on this device.')
        return
      }
      const camera = devices.find((d) => /back|rear|environment/i.test(d.label)) || devices[0]

      if (!scannerRef.current) {
        scannerRef.current = new Html5Qrcode(READER_ID)
      }
      await scannerRef.current.start(
        camera.id,
        { fps: 10, qrbox: { width: 240, height: 240 } },
        async (text) => {
          await stopScanner()
          processCode(text)
        },
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
        reason = 'No camera detected on this device.'
      else if (low.includes('in use') || low.includes('notreadable') || low.includes('already'))
        reason = 'Camera is in use by another app or tab. Close it and try again.'
      else if (low.includes('secure') || low.includes('https') || low.includes('insecure'))
        reason = 'Camera requires a secure connection. Use http://localhost.'
      setCameraError(reason)
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
  }

  const startEditStatus = () => {
    setStatusForm({ condition: result.condition, lifecycleStatus: result.lifecycleStatus })
    setEditingStatus(true)
  }

  const cancelEditStatus = () => { setEditingStatus(false); setStatusHint('') }

  const handleLifecycleChange = (e) => {
    const value = e.target.value
    setStatusHint('')
    const kind = !isAdmin && value !== result.lifecycleStatus ? REQUEST_FOR_STATUS[value] : null
    if (!kind) { setStatusForm((p) => ({ ...p, lifecycleStatus: value })); return }
    if (kind === 'disposal' && !DISPOSABLE_CONDITIONS.includes(result.condition)) {
      setStatusHint('Only assets marked REPAIRABLE or UNSERVICEABLE can be disposed — save that condition first, then request disposal.')
      return
    }
    if (users.length === 0) getUsers().then(({ data }) => setUsers(data)).catch(() => {})
    setRequestKind(kind)
  }

  const sendRequest = async (payload, idempotencyKey) => {
    const create = requestKind === 'maintenance' ? createMaintenance : createDisposal
    await create(payload, idempotencyKey)
    setEditingStatus(false)
    show(`${requestKind === 'maintenance' ? 'Maintenance' : 'Disposal'} request sent — an administrator needs to approve it.`, 'success')
  }

  const lifecycleOptions = Object.keys(LIFECYCLE_BADGE).filter(
    (s) => isAdmin || s !== 'TRANSFERRED' || result?.lifecycleStatus === 'TRANSFERRED')

  const saveStatus = async () => {
    setSavingStatus(true)
    try {
      const { data } = await updateAssetStatus(result.id, statusForm.condition, statusForm.lifecycleStatus)
      setResult(data)
      dispatch(updateAssetInStore(data))
      setEditingStatus(false)
      show('Asset status updated.', 'success')
    } catch (err) {
      show(err.response?.data?.message || 'Failed to update status.', 'error')
    } finally {
      setSavingStatus(false)
    }
  }

  const qrValue = result ? `asset:${result.id}:${result.propertyNumber}` : ''

  return (
    <MainLayout>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">

        {/* ── Left: Scanner + manual input ─────────────────────────────── */}
        <div className="space-y-4">
          {/* Camera panel */}
          <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 overflow-hidden">
            <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800">
              <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Camera Scanner</p>
              <p className="text-xs text-slate-400 dark:text-zinc-500 mt-px">Point your camera at an ICT asset QR code</p>
            </div>

            {/* Video viewport */}
            <div className="relative bg-slate-100 dark:bg-zinc-950" style={{ minHeight: 280 }}>
              <div id={READER_ID} className="w-full" />

              {!scanning && !cameraError && (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-slate-100 dark:bg-zinc-950">
                  <div className="w-20 h-20 rounded-2xl bg-slate-200 dark:bg-zinc-800 flex items-center justify-center">
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 text-slate-400 dark:text-zinc-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v1m6 11h2m-6 0h-2v4m0-11v3m0 0h.01M12 12h4.01M16 20h4M4 12h4m12 0h.01M5 8H3a2 2 0 00-2 2v9a2 2 0 002 2h9a2 2 0 002-2v-3M9 4H7a2 2 0 00-2 2v3a2 2 0 002 2h2a2 2 0 002-2V6a2 2 0 00-2-2z" />
                    </svg>
                  </div>
                  <p className="text-sm text-slate-400 dark:text-zinc-500 text-center px-8">
                    Activate your camera to scan a QR code
                  </p>
                  <Button size="md" onClick={startScanner}>
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M3 4a1 1 0 011-1h3a1 1 0 011 1v3a1 1 0 01-1 1H4a1 1 0 01-1-1V4zm2 2V5h1v1H5zM3 13a1 1 0 011-1h3a1 1 0 011 1v3a1 1 0 01-1 1H4a1 1 0 01-1-1v-3zm2 2v-1h1v1H5zM13 3a1 1 0 00-1 1v3a1 1 0 001 1h3a1 1 0 001-1V4a1 1 0 00-1-1h-3zm1 2v1h1V5h-1zM11 7a1 1 0 112 0v1h1a1 1 0 110 2h-2a1 1 0 01-1-1V7zM7 11a1 1 0 100 2h1v1a1 1 0 102 0v-2a1 1 0 00-1-1H7zM13 11a1 1 0 100 2h.01a1 1 0 100-2H13zM15 13a1 1 0 100 2h.01a1 1 0 100-2H15zM13 15a1 1 0 100 2h.01a1 1 0 100-2H13z" clipRule="evenodd" />
                    </svg>
                    Start Scanner
                  </Button>
                </div>
              )}

              {cameraError && !scanning && (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 p-6 bg-slate-100 dark:bg-zinc-950">
                  <div className="w-12 h-12 rounded-full bg-red-50 dark:bg-red-950 flex items-center justify-center">
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 text-red-500 dark:text-red-400" viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                    </svg>
                  </div>
                  <p className="text-sm text-red-500 dark:text-red-400 text-center">{cameraError}</p>
                </div>
              )}
            </div>

            {scanning && (
              <div className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                  <p className="text-sm text-slate-500 dark:text-zinc-400">Scanning for QR code…</p>
                </div>
                <Button variant="secondary" size="sm" onClick={stopScanner}>Stop</Button>
              </div>
            )}
          </div>

          {/* Manual entry */}
          <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 p-5">
            <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300 mb-1">Manual Code Entry</p>
            <p className="text-xs text-slate-400 dark:text-zinc-500 mb-3">Enter a Property Number or PAR Number to search directly.</p>
            <form onSubmit={handleManualSearch} className="flex gap-2">
              <input
                type="text"
                placeholder="e.g. COA-2024-001"
                value={manualCode}
                onChange={(e) => setManualCode(e.target.value)}
                className="flex-1 rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3.5 py-2 text-sm text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150"
              />
              <Button type="submit" size="md">Search</Button>
            </form>
          </div>
        </div>

        {/* ── Right: Result panel ───────────────────────────────────────── */}
        <div>
          {!result && !notFound && (
            <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 h-full flex flex-col items-center justify-center gap-3 p-8 min-h-[320px]">
              <div className="w-16 h-16 rounded-2xl bg-slate-100 dark:bg-zinc-800 flex items-center justify-center">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-8 w-8 text-slate-300 dark:text-zinc-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                </svg>
              </div>
              <p className="text-sm text-slate-400 dark:text-zinc-600 text-center">
                Scan a QR code or enter a Property Number or PAR Number to view asset details.
              </p>
            </div>
          )}

          {notFound && (
            <div className="bg-white dark:bg-zinc-900 rounded-xl border border-red-200 dark:border-red-800/40 p-8 flex flex-col items-center justify-center gap-3 min-h-[320px] animate-fade-slide">
              <div className="w-12 h-12 rounded-full bg-red-50 dark:bg-red-950 flex items-center justify-center">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 text-red-500 dark:text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                </svg>
              </div>
              <p className="text-sm font-semibold text-red-500 dark:text-red-400">Asset Not Found</p>
              <p className="text-xs text-slate-400 dark:text-zinc-500 text-center">
                No asset matches this code. Verify the property number and try again.
              </p>
              <Button variant="secondary" size="sm" onClick={handleClear}>Clear</Button>
            </div>
          )}

          {result && (
            <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 overflow-hidden animate-fade-slide">
              <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="w-2 h-2 rounded-full bg-emerald-400" />
                  <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Asset Found</p>
                </div>
                <div className="flex items-center gap-2">
                  <Button size="sm" onClick={() => navigate(`/assets`)}>
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5 mr-1" viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" />
                    </svg>
                    View Assets
                  </Button>
                  <Button size="sm" variant="secondary" onClick={() => navigate(`/asset-history`)}>
                    History
                  </Button>
                  <button
                    onClick={() => printAssetQR(result)}
                    className="flex items-center gap-1.5 text-xs font-semibold text-brand-500 dark:text-brand-400 hover:text-brand-600 dark:hover:text-brand-300 transition-colors"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
                    </svg>
                    Print QR
                  </button>
                  <button onClick={handleClear} className="text-xs text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-300 transition-colors">Clear</button>
                </div>
              </div>

              <div className="p-5 space-y-5">
                {/* QR code */}
                <div className="flex justify-center">
                  <div className="bg-white p-4 rounded-xl inline-block ring-1 ring-slate-200 dark:ring-zinc-700">
                    <QRCodeSVG
                      id="qr-result-svg"
                      value={qrValue}
                      size={140}
                      bgColor="#ffffff"
                      fgColor="#111827"
                      level="H"
                    />
                  </div>
                </div>

                {/* Status */}
                {editingStatus ? (
                  <div className="rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-950 p-3.5 space-y-3">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      <label className="block">
                        <span className="text-2xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-wider">Condition</span>
                        <select
                          value={statusForm.condition}
                          onChange={(e) => setStatusForm((p) => ({ ...p, condition: e.target.value }))}
                          className="mt-1 w-full rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3 py-1.5 text-sm text-slate-700 dark:text-zinc-200 focus:outline-none focus:ring-2 focus:ring-brand-500"
                        >
                          {Object.keys(CONDITION_BADGE).map((c) => <option key={c} value={c}>{c}</option>)}
                        </select>
                      </label>
                      <label className="block">
                        <span className="text-2xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-wider">Lifecycle Status</span>
                        <select
                          value={statusForm.lifecycleStatus}
                          onChange={handleLifecycleChange}
                          className="mt-1 w-full rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3 py-1.5 text-sm text-slate-700 dark:text-zinc-200 focus:outline-none focus:ring-2 focus:ring-brand-500"
                        >
                          {lifecycleOptions.map((s) => (
                            <option key={s} value={s} disabled={!isAdmin && s === 'TRANSFERRED'}>
                              {s.replace('_', ' ')}{!isAdmin && REQUEST_FOR_STATUS[s] && s !== result.lifecycleStatus ? ' — request…' : ''}
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
                  <div className="flex items-center justify-between gap-2 flex-wrap">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${CONDITION_BADGE[result.condition] || ''}`}>
                        {result.condition}
                      </span>
                      <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${LIFECYCLE_BADGE[result.lifecycleStatus] || ''}`}>
                        {result.lifecycleStatus?.replace('_', ' ')}
                      </span>
                    </div>
                    <button
                      onClick={startEditStatus}
                      className="flex items-center gap-1 text-xs font-semibold text-brand-500 dark:text-brand-400 hover:text-brand-600 dark:hover:text-brand-300 transition-colors"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                        <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                      </svg>
                      Update Status
                    </button>
                  </div>
                )}

                {/* Fields */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3">
                  {[
                    { label: 'Property Number', value: result.propertyNumber },
                    { label: 'PAR Number',      value: result.parNumber },
                    { label: 'Description',     value: result.description, full: true },
                    { label: 'Serial Number',   value: result.serialNumber },
                    { label: 'Category',        value: result.category?.categoryName },
                    { label: 'Office',          value: result.office?.officeName },
                    { label: 'Location',        value: result.location },
                    { label: 'Accountable',     value: result.accountablePerson?.fullName },
                    { label: 'Current User',    value: result.currentUser?.fullName },
                    { label: 'Unit Value',      value: php(result.unitValue) },
                    { label: 'Quantity',        value: result.quantity },
                    { label: 'Acquisition Date', value: fmt(result.acquisitionDate) },
                    ...(result.carryingAmount != null ? [
                      { label: 'Accumulated Depreciation', value: php(result.accumulatedDepreciation) },
                      { label: 'Carrying Amount',          value: php(result.carryingAmount) },
                    ] : []),
                    { label: 'Specifications',  value: result.specifications, full: true, multiline: true },
                    { label: 'Remarks',         value: result.remarks },
                  ].filter((f) => f.value).map(({ label, value, full, multiline }) => (
                    <div key={label} className={full ? 'col-span-2' : ''}>
                      <p className="text-2xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-wider">{label}</p>
                      <p className={`text-sm text-slate-700 dark:text-zinc-200 mt-0.5 leading-snug ${multiline ? 'whitespace-pre-line' : ''}`}>{value}</p>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
      {requestKind === 'maintenance' && result && (
        <AddMaintenanceModal requestMode presetAssetId={result.id} assets={[result]} users={users}
          onClose={() => setRequestKind(null)} onSave={sendRequest} />
      )}
      {requestKind === 'disposal' && result && (
        <AddDisposalModal requestMode presetAssetId={result.id} assets={[result]} users={users}
          onClose={() => setRequestKind(null)} onSave={sendRequest} />
      )}
    </MainLayout>
  )
}

export default QRScanner
