import { useState, useEffect, useRef } from 'react'
import { HEADER_OFFSET } from '../../components/layout/layoutSizes'
import { useNavigate } from 'react-router-dom'
import { getMaintenanceByAsset } from '../../services/maintenanceService'
import { getDisposalByAsset } from '../../services/disposalService'
import { getHistoryByAsset } from '../../services/assetHistoryService'
import { getPropertyCard } from '../../services/propertyCardService'
import { getAssetById } from '../../services/assetService'
import { openPrintWindow, printPropertyCards, exportPropertyCardsExcel } from '../../utils/propertyCardExport'
import { getLatestRecommendation, generateRecommendation } from '../../services/aiRecommendationService'
import { useEventStream } from '../../hooks/useEventStream'
import AssetQrModal from './AssetQrModal'
import { Badge, CONDITION_BADGE, LIFECYCLE_BADGE } from './assetBadges'
import EvidenceModal from '../../components/common/EvidenceModal'
import ReturnPapers, { hasReturnPapers } from '../../components/common/ReturnPapers'
import { getReturnPapers } from '../../services/transferService'

const TAB_LABELS = { details: 'Details', history: 'Lifecycle', specs: 'Specifications', ai: 'AI Insight', maintenance: 'Maintenance', papers: 'PARs & Return Slips' }
// Shorter labels for phones so every tab fits on one row at any Text Size
const TAB_LABELS_SHORT = { details: 'Details', history: 'History', specs: 'Specs', ai: 'AI', maintenance: 'Repairs', papers: 'PARs' }

const RECOMMENDATION_BADGE = {
  MAINTAIN:            'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 ring-1 ring-emerald-500/20',
  MONITOR:             'bg-blue-500/10 text-blue-700 dark:text-blue-300 ring-1 ring-blue-500/20',
  REPAIR:              'bg-amber-500/10 text-amber-700 dark:text-amber-300 ring-1 ring-amber-500/20',
  REVIEW_FOR_DISPOSAL: 'bg-orange-500/10 text-orange-700 dark:text-orange-300 ring-1 ring-orange-500/20',
  BUDGET_PRIORITY:     'bg-red-500/10 text-red-700 dark:text-red-300 ring-1 ring-red-500/20',
}


function fmt(dt) {
  if (!dt) return 'N/A'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}
// The category's expected useful life, counted from the acquisition date.
function expectedLife(asset) {
  const years = asset.category?.usefulLifeYears
  if (!years) return 'Not set for this category'
  const label = `${years} year${years === 1 ? '' : 's'}`
  if (!asset.acquisitionDate) return label
  const end = new Date(asset.acquisitionDate)
  end.setFullYear(end.getFullYear() + years)
  const when = end.toLocaleDateString('en-PH', { year: 'numeric', month: 'short' })
  return end < new Date() ? `${label} · ended ${when}` : `${label} · ends ${when}`
}
function php(v) {
  if (v == null) return 'N/A'
  return '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 })
}

// onDelete is passed for admins only.
// listAsset: the row's record. The list only carries a summary, so the full record (specs,
// remarks, PAR, QR data, ...) is loaded here; Edit waits for it, or saving would drop fields.
export default function AssetDrawer({ asset: listAsset, onClose, onEdit, onDelete, exiting }) {
  const [full, setFull] = useState(null)
  useEffect(() => {
    let alive = true
    setFull(null)
    getAssetById(listAsset.id).then(({ data }) => { if (alive) setFull(data) }).catch(() => {})
    return () => { alive = false }
  }, [listAsset.id, listAsset.updatedAt])
  const asset = full || listAsset
  const navigate = useNavigate()
  const [maintenance, setMaintenance] = useState([])
  const [disposal, setDisposal]       = useState([])
  const [history, setHistory]         = useState([])
  const [papers, setPapers]           = useState(null) // return slips and PARs from end-user changes
  const [tab, setTab]                 = useState('details')
  const [recommendation, setRecommendation] = useState(null)
  const [aiLoading, setAiLoading]     = useState(false)
  const [aiError, setAiError]         = useState('')
  // The server makes one in the background when there is none yet (see AiAutoGenerator)
  const [aiGenerating, setAiGenerating] = useState(false)
  // Why nothing is coming (e.g. the AI's daily limit is used up) - shown instead of waiting
  const [aiNotice, setAiNotice]       = useState('')
  const [showQr, setShowQr]           = useState(false)
  const [showEvidence, setShowEvidence] = useState(false)
  const [cardLoading, setCardLoading] = useState(false)
  const [cardError, setCardError]     = useState('')
  const isFirstRender = useRef(true)

  // Fetches this asset's Property Card, then prints or exports it. The print window opens on the
  // click itself (a window opened after the request returns would be blocked as a popup).
  const withPropertyCard = (kind) => {
    const win = kind === 'print' ? openPrintWindow() : null
    setCardLoading(true)
    setCardError('')
    getPropertyCard(asset.id)
      .then(({ data }) => (kind === 'print' ? printPropertyCards([data], win) : exportPropertyCardsExcel([data])))
      .catch((err) => {
        win?.close()
        setCardError(err.response?.data?.message || err.message || 'Could not load the Property Card.')
      })
      .finally(() => setCardLoading(false))
  }

  useEffect(() => {
    if (!asset) return

    const fetchAssetData = () => {
      getHistoryByAsset(asset.id).then(({ data }) => setHistory(data)).catch(() => {})
      getReturnPapers(asset.id).then(({ data }) => setPapers(data)).catch(() => setPapers(null))
      // Loaded whatever the current condition, so a repaired asset still shows its records.
      getMaintenanceByAsset(asset.id).then(({ data }) => setMaintenance(data)).catch(() => setMaintenance([]))
      getDisposalByAsset(asset.id).then(({ data }) => setDisposal(data)).catch(() => setDisposal([]))
      setRecommendation(null)
      setAiError('')
      setAiGenerating(false)
      setAiNotice('')
      loadRecommendation(asset.id)
    }

    // Only the drawer's very first render (its entrance) needs to wait - a
    // subsequent asset swap while it's already open doesn't replay the
    // slide-in/fade-in, so there's no animation for the fetch's re-renders
    // to compete with and no reason to add latency there.
    if (isFirstRender.current) {
      isFirstRender.current = false
      // Longer than the drawer's slide-in-drawer entrance (320ms) so the
      // fetch responses' re-renders land after the CSS transition settles,
      // instead of contending with it on the main thread mid-animation.
      const timer = setTimeout(fetchAssetData, 350)
      return () => clearTimeout(timer)
    }

    fetchAssetData()
  }, [listAsset.id]) // eslint-disable-line react-hooks/exhaustive-deps

  // Esc closes the drawer - but not while one of its own dialogs (QR, photos) is open on top.
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape' && !showQr && !showEvidence) onClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose, showQr, showEvidence])

  // If the server never announces a result (e.g. the AI quota ran out), offer the button again.
  useEffect(() => {
    if (!aiGenerating) return
    const timer = setTimeout(() => setAiGenerating(false), 90_000)
    return () => clearTimeout(timer)
  }, [aiGenerating])

  useEventStream('ai', ({ action, id, data }) => {
    if (data?.kind !== 'recommendation' || !asset || id !== asset.id) return
    if (action === 'FAILED') { setAiGenerating(false); setAiNotice(data.message || '') }
    else loadRecommendation(asset.id)
  })

  function loadRecommendation(assetId) {
    getLatestRecommendation(assetId)
      .then(({ data }) => { setRecommendation(data); setAiGenerating(false); setAiNotice('') })
      .catch((err) => {
        const body = err.response?.data
        setAiGenerating(Boolean(body?.generating))
        setAiNotice(body?.unavailable || '')
      })
  }

  const handleGenerate = () => {
    setAiLoading(true)
    setAiError('')
    setAiNotice('')
    generateRecommendation(asset.id)
      .then(({ data }) => setRecommendation(data))
      .catch((err) => setAiError(err.response?.data?.message || 'Failed to generate recommendation.'))
      .finally(() => setAiLoading(false))
  }

  if (!asset) return null

  const tabs = ['details', 'history', 'specs', 'ai',
    ...(asset.condition === 'REPAIRABLE' || maintenance.length > 0 ? ['maintenance'] : []),
    ...(hasReturnPapers(papers) ? ['papers'] : []),
  ]
  const so = (v) => (v > 0 ? `+${v}` : String(v))

  return (
    <>
      {/* Blur is static - animating opacity on the same element that carries
          backdrop-blur forces the browser to resample the (busy) table behind
          it every frame. It snaps in instantly; only the tint below fades. */}
      <div className="fixed inset-0 z-30 backdrop-blur-sm pointer-events-none" style={{ top: HEADER_OFFSET }} />
      <div
        className={`fixed inset-0 z-30 bg-zinc-950/20 ${exiting ? 'animate-fade-out' : 'animate-fade-in'}`}
        style={{ top: HEADER_OFFSET }}
        onClick={onClose}
      />
      {/* Centered window over the page (below the top bar); clicks on the empty area around
          it fall through to the backdrop, which closes it. */}
      <div className="fixed inset-x-0 bottom-0 z-40 flex items-center justify-center p-3 sm:p-6 pointer-events-none" style={{ top: HEADER_OFFSET }}>
      <div
        role="dialog" aria-modal="true" aria-label={`Asset details: ${asset.propertyNumber || ''} ${asset.description || ''}`}
        className={`pointer-events-auto w-full max-w-[56rem] max-h-full bg-white dark:bg-zinc-950 border border-slate-200 dark:border-zinc-800 rounded-xl flex flex-col shadow-2xl overflow-hidden ${exiting ? 'animate-fade-out' : 'animate-scale-in'}`}
      >
        {/* Header */}
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2 px-5 sm:px-6 py-3 border-b border-slate-200 dark:border-zinc-800 flex-shrink-0">
          {/* Name, then the property number and status on one line */}
          <div className="flex-1 min-w-[14rem]">
            <h2 className="text-lg font-semibold text-slate-900 dark:text-white leading-snug">{asset.description}</h2>
            <div className="flex items-center gap-x-2 gap-y-1 mt-1 flex-wrap text-sm">
              <span className="text-slate-600 dark:text-zinc-400">Property No.</span>
              <span className="font-mono font-semibold text-slate-900 dark:text-zinc-100">{asset.propertyNumber}</span>
              <span className="text-slate-300 dark:text-zinc-600" aria-hidden="true">·</span>
              <Badge map={CONDITION_BADGE} value={asset.condition} />
              <Badge map={LIFECYCLE_BADGE} value={asset.lifecycleStatus} />
            </div>
          </div>
          {/* Labelled buttons rather than bare icons, so every user can tell what they do */}
          <div className="order-last sm:order-none w-full sm:w-auto grid grid-cols-3 sm:flex items-center gap-1.5">
            <DrawerAction onClick={() => full && onEdit(full)} disabled={!full} label={full ? 'Edit asset' : 'Loading…'}
              icon={<path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />} />
            <DrawerAction onClick={() => setShowQr(true)} label="QR sticker"
              icon={<path fillRule="evenodd" d="M3 4a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H4a1 1 0 01-1-1V4zm2 1v2h2V5H5zM3 12a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H4a1 1 0 01-1-1v-4zm2 1v2h2v-2H5zM11 4a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1V4zm2 1v2h2V5h-2zM11 12h2v2h-2v-2zM15 12h2v2h-2v-2zM11 16h2v2h-2v-2zM15 16h2v2h-2v-2z" clipRule="evenodd" />} />
            <DrawerAction onClick={() => setShowEvidence(true)} label="Photos"
              icon={<path fillRule="evenodd" d="M4 5a2 2 0 00-2 2v8a2 2 0 002 2h12a2 2 0 002-2V7a2 2 0 00-2-2h-1.586a1 1 0 01-.707-.293l-1.121-1.121A2 2 0 0011.172 3H8.828a2 2 0 00-1.414.586L6.293 4.707A1 1 0 015.586 5H4zm6 9a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />} />
          </div>
          <div className="flex items-center gap-1 flex-shrink-0">
            <button onClick={onClose} aria-label="Close asset details" title="Close (Esc)" className="p-1.5 rounded-md text-slate-600 dark:text-zinc-400 hover:text-slate-900 dark:hover:text-zinc-100 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
            </button>
          </div>
        </div>

        {/* Tabs */}
        {/* One row of equal-width tabs; phones get the short labels */}
        <div className="grid grid-flow-col auto-cols-fr sm:flex sm:gap-1 border-b border-slate-200 dark:border-zinc-800 px-2 sm:px-6 flex-shrink-0" role="tablist">
          {tabs.map((t) => (
            <button key={t} onClick={() => setTab(t)} role="tab" aria-selected={tab === t} title={TAB_LABELS[t]}
              className={`min-w-0 px-1 sm:px-4 py-2.5 text-xs sm:text-sm font-semibold text-center whitespace-nowrap overflow-hidden text-ellipsis transition-all border-b-2 -mb-px ${
                tab === t ? 'border-slate-900 dark:border-white text-slate-900 dark:text-white' : 'border-transparent text-slate-500 dark:text-zinc-400 hover:text-slate-700 dark:hover:text-zinc-200'
              }`}>
              <span className="sm:hidden">{TAB_LABELS_SHORT[t] || TAB_LABELS[t]}</span>
              <span className="hidden sm:inline">{TAB_LABELS[t] || t}</span>
            </button>
          ))}
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 sm:px-6 py-4">
          {!full && (tab === 'details' || tab === 'specs') ? (
            <div className="space-y-3 py-2" aria-busy="true">
              {Array.from({ length: 6 }).map((_, i) => <div key={i} className="animate-pulse h-4 rounded bg-slate-200 dark:bg-zinc-800" style={{ width: `${90 - i * 8}%` }} />)}
            </div>
          ) : null}
          {full && tab === 'details' && (
            <div>
              {/* Two columns of sections when there's room; one on phones */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-x-10 gap-y-3">
              {/* Kept short so the whole tab fits without scrolling on a laptop screen: the
                  property number is in the header, and fields that belong together share a row. */}
              <div className="space-y-3">
                <section aria-labelledby="sec-id">
                  <h3 id="sec-id" className={SECTION}>Identification</h3>
                  <Field label="PAR Number"        value={asset.parNumber} mono />
                  <Field label="Serial Number"     value={asset.serialNumber} mono />
                  <Field label="Category"          value={asset.category?.categoryName} />
                  <Field label="Article"           value={asset.article?.articleName} />
                </section>
                <section aria-labelledby="sec-value">
                  <h3 id="sec-value" className={SECTION}>Acquisition &amp; count</h3>
                  <Field label="Acquired"          value={`${fmt(asset.acquisitionDate)} · ${php(asset.unitValue)}`} />
                  <Field label="Expected life"     value={expectedLife(asset)} />
                  <Field label="Quantity"          value={`${asset.quantity ?? 1} on Property Card · ${asset.physicalCount ?? 'N/A'} counted`} />
                  <Field label="Shortage/Overage"  value={`${so(Number(asset.shortageOverageQty ?? 0))} · ${php(asset.shortageOverageValue ?? 0)}`} />
                </section>
              </div>
              <div className="space-y-3">
                <section aria-labelledby="sec-where">
                  <h3 id="sec-where" className={SECTION}>Assignment</h3>
                  <Field label="Office"            value={asset.office?.officeName} />
                  <Field label="Room / Location"   value={asset.location} />
                  <Field label="Accountable Person" value={asset.accountablePerson?.fullName} />
                  <Field label="Current User"      value={asset.currentUser?.fullName} />
                </section>
                <section aria-labelledby="sec-notes">
                  <h3 id="sec-notes" className={SECTION}>Notes &amp; record</h3>
                  <Field label="Remarks"           value={asset.remarks} />
                  <Field label="Added / Updated"   value={`${fmt(asset.createdAt)} · ${fmt(asset.updatedAt)}`} />
                </section>
              </div>
              </div>
              <div className="flex flex-wrap gap-2 mt-4 pt-3 border-t border-slate-200 dark:border-zinc-800">
              {asset.condition === 'REPAIRABLE' && (
                <button onClick={() => navigate(`/maintenance?assetId=${asset.id}`)}
                  className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-amber-500/10 border border-amber-500/30 text-amber-800 dark:text-amber-300 text-sm font-medium hover:bg-amber-500/20 transition-all">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" /></svg>
                  View Maintenance Records
                </button>
              )}
              {asset.condition === 'UNSERVICEABLE' && (
                <button onClick={() => navigate(`/disposal?assetId=${asset.id}`)}
                  className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-red-500/10 border border-red-500/30 text-red-700 dark:text-red-300 text-sm font-medium hover:bg-red-500/20 transition-all">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" /></svg>
                  View Disposal Records
                </button>
              )}
              {onDelete && (
                <button onClick={() => onDelete(asset)}
                  className="sm:ml-auto flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg border border-red-500/30 text-red-700 dark:text-red-300 text-sm font-medium hover:bg-red-500/10 transition-all">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" /></svg>
                  Delete Asset
                </button>
              )}
              </div>
            </div>
          )}

          {tab === 'history' && (() => {
            const historyItems = history.map((h) => ({
              id: `h-${h.id}`,
              date: h.eventDate,
              sortKey: h.eventDate,
              type: 'history',
              title: h.eventType,
              meta: `By: ${h.performedBy?.fullName || h.performedBy?.username || 'N/A'}`,
              note: h.notes,
            }))
            const disposalItems = disposal.map((d) => ({
              id: `d-${d.id}`,
              date: d.inspectionDate,
              // inspectionDate is a date-only field (no time-of-day), so it can't be
              // reliably compared against history's full-timestamp eventDate when both
              // fall on the same day - updatedAt/createdAt carry real time-of-day and
              // reflect when the record was actually last touched.
              sortKey: d.updatedAt || d.createdAt || d.inspectionDate,
              type: 'disposal',
              title: d.recommendedMethod,
              status: d.disposalStatus,
              note: d.reason,
            }))
            const maintenanceItems = maintenance.map((m) => ({
              id: `m-${m.id}`,
              date: m.maintenanceDate,
              sortKey: m.updatedAt || m.createdAt || m.maintenanceDate,
              type: 'maintenance',
              title: m.maintenanceType,
              status: m.status,
              note: m.findings,
              cost: m.cost,
            }))
            const combined = [...historyItems, ...disposalItems, ...maintenanceItems].sort((a, b) => new Date(b.sortKey) - new Date(a.sortKey))
            // A Property Card exists only once the asset has been transferred somewhere.
            const wasTransferred = history.some((h) => h.eventType === 'TRANSFERRED' && h.toOffice)

            return (
              <div className="space-y-2">
                {wasTransferred && (
                  <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-800/40 px-3 py-2.5 mb-3">
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Property Card</p>
                      <p className="text-xs text-slate-500 dark:text-zinc-400">Every transfer: to whom and to which office.</p>
                      {cardError && <p className="text-xs text-red-500 mt-1" role="alert">{cardError}</p>}
                    </div>
                    <div className="flex gap-1.5">
                      <button type="button" disabled={cardLoading} onClick={() => withPropertyCard('print')}
                        className="px-2.5 py-1.5 rounded-md text-xs font-semibold border border-slate-200 dark:border-zinc-700 text-slate-600 dark:text-zinc-300 hover:bg-white dark:hover:bg-zinc-800 disabled:opacity-50 transition-colors">
                        Print / PDF
                      </button>
                      <button type="button" disabled={cardLoading} onClick={() => withPropertyCard('excel')}
                        className="px-2.5 py-1.5 rounded-md text-xs font-semibold border border-slate-200 dark:border-zinc-700 text-slate-600 dark:text-zinc-300 hover:bg-white dark:hover:bg-zinc-800 disabled:opacity-50 transition-colors">
                        Excel
                      </button>
                    </div>
                  </div>
                )}
                {combined.length === 0
                  ? <p className="text-sm text-slate-600 dark:text-zinc-400 py-8 text-center">No lifecycle events recorded.</p>
                  : combined.map((item) => (
                    <div key={item.id} className="px-3.5 py-3 rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-900">
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-xs font-semibold text-slate-700 dark:text-zinc-200">
                          {item.type === 'disposal' ? `Disposal – ${item.title}` :
                           item.type === 'maintenance' ? `Maintenance – ${item.title}` : item.title}
                        </span>
                        {item.type === 'disposal' && (
                          <span className={`inline-flex px-1.5 py-0.5 rounded-full text-xs font-semibold ${
                            item.status === 'COMPLETED' ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300' :
                            item.status === 'APPROVED'  ? 'bg-blue-500/10 text-blue-700 dark:text-blue-300'       : 'bg-amber-500/10 text-amber-700 dark:text-amber-300'
                          }`}>{item.status}</span>
                        )}
                        {item.type === 'maintenance' && (
                          <span className={`inline-flex px-1.5 py-0.5 rounded-full text-xs font-semibold ${
                            item.status === 'COMPLETED' ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300' :
                            item.status === 'ONGOING'   ? 'bg-amber-500/10 text-amber-700 dark:text-amber-300'    : 'bg-blue-500/10 text-blue-700 dark:text-blue-300'
                          }`}>{item.status}</span>
                        )}
                        {item.type === 'history' && (
                          <span className="text-xs text-slate-600 dark:text-zinc-400">{fmt(item.date)}</span>
                        )}
                      </div>
                      {item.type === 'disposal' && <p className="text-xs text-slate-600 dark:text-zinc-400 mt-0.5">Inspected: {fmt(item.date)}</p>}
                      {item.type === 'maintenance' && <p className="text-xs text-slate-600 dark:text-zinc-400 mt-0.5">{fmt(item.date)}{item.cost != null ? ` · ${php(item.cost)}` : ''}</p>}
                      {item.type === 'history' && <p className="text-xs text-slate-500 dark:text-zinc-400 mt-1">{item.meta}</p>}
                      {item.note && <p className="text-xs text-slate-500 dark:text-zinc-400 mt-0.5 italic">{item.note}</p>}
                    </div>
                  ))
                }
              </div>
            )
          })()}

          {tab === 'papers' && hasReturnPapers(papers) && <ReturnPapers papers={papers} />}

          {full && tab === 'specs' && (
            asset.specifications ? (
              <p className="text-sm text-slate-700 dark:text-zinc-200 whitespace-pre-line break-words bg-slate-50 dark:bg-zinc-900 border border-slate-200 dark:border-zinc-800 rounded-lg px-3.5 py-3 leading-relaxed">
                {asset.specifications}
              </p>
            ) : (
              <div className="flex flex-col items-center justify-center py-10 gap-3 text-center">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-9 w-9 text-slate-200 dark:text-zinc-800" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                <p className="text-sm text-slate-600 dark:text-zinc-400">No technical specifications recorded for this asset.</p>
                <button onClick={() => full && onEdit(full)} disabled={!full}
                  className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-brand-500/10 border border-brand-500/30 text-brand-700 dark:text-brand-300 text-sm font-medium hover:bg-brand-500/20 transition-all">
                  Add Specifications
                </button>
              </div>
            )
          )}

          {tab === 'ai' && (
            <div className="space-y-3">
              {aiError && (
                <div className="text-xs text-red-700 dark:text-red-300 bg-red-500/10 border border-red-500/30 rounded-lg px-3.5 py-2.5">
                  {aiError}
                </div>
              )}

              {recommendation ? (
                <>
                  <div className="flex items-center justify-between gap-2">
                    <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${RECOMMENDATION_BADGE[recommendation.recommendation] || ''}`}>
                      {recommendation.recommendation?.replace(/_/g, ' ')}
                    </span>
                    <span className="text-xs text-slate-600 dark:text-zinc-400">{fmt(recommendation.generatedAt)}</span>
                  </div>

                  <p className="text-sm text-slate-600 dark:text-zinc-300 leading-relaxed">{recommendation.rationale}</p>

                  {/* Label above value in small tiles - side-by-side label/value rows overlapped on phones */}
                  <dl className="grid grid-cols-2 gap-2 pt-1">
                    {[
                      ['Asset Age', `${recommendation.assetAgeYears} yrs`],
                      ['Repair Cost', php(recommendation.totalRepairCost)],
                      ['Repair Frequency', recommendation.repairFrequency],
                      ['Condition Score', recommendation.conditionScore],
                    ].map(([label, value]) => (
                      <div key={label} className="min-w-0 rounded-lg bg-slate-50 dark:bg-zinc-800/60 border border-slate-100 dark:border-zinc-800 px-3 py-2">
                        <dt className="text-xs text-slate-500 dark:text-zinc-400">{label}</dt>
                        <dd className="text-sm font-semibold text-slate-900 dark:text-zinc-100 mt-0.5 break-words">{value ?? 'N/A'}</dd>
                      </div>
                    ))}
                  </dl>

                  <button onClick={handleGenerate} disabled={aiLoading}
                    className="w-full mt-2 flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 text-slate-600 dark:text-zinc-300 text-sm font-medium hover:bg-slate-200 dark:hover:bg-zinc-700 transition-all disabled:opacity-50">
                    {aiLoading ? 'Regenerating…' : 'Regenerate Recommendation'}
                  </button>
                </>
              ) : (
                <div className="flex flex-col items-center justify-center py-10 gap-3 text-center">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-9 w-9 text-slate-200 dark:text-zinc-800" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
                  </svg>
                  {aiNotice && !aiGenerating && (
                    <p role="status" className="max-w-xs text-sm text-amber-800 dark:text-amber-300 bg-amber-50 dark:bg-amber-500/10 border border-amber-200 dark:border-amber-500/30 rounded-lg px-3.5 py-2.5">
                      {aiNotice}
                    </p>
                  )}
                  {aiGenerating ? (
                    <p className="text-sm text-slate-500 dark:text-zinc-400" role="status">
                      Preparing a recommendation… it will appear here in a moment.
                    </p>
                  ) : (
                    <>
                      <p className="text-sm text-slate-600 dark:text-zinc-400">No AI recommendation generated yet.</p>
                      <button onClick={handleGenerate} disabled={aiLoading}
                        className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-brand-500/10 border border-brand-500/30 text-brand-700 dark:text-brand-300 text-sm font-medium hover:bg-brand-500/20 transition-all disabled:opacity-50">
                        {aiLoading ? 'Generating…' : 'Generate Recommendation'}
                      </button>
                    </>
                  )}
                </div>
              )}
            </div>
          )}

          {tab === 'maintenance' && (
            <div className="space-y-2">
              {maintenance.length === 0
                ? <p className="text-sm text-slate-600 dark:text-zinc-400 py-8 text-center">No maintenance records.</p>
                : maintenance.map((m) => (
                  <div key={m.id} className="px-3.5 py-3 rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-900">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs font-semibold text-slate-700 dark:text-zinc-200">{m.maintenanceType}</span>
                      <span className={`inline-flex px-1.5 py-0.5 rounded-full text-xs font-semibold ${
                        m.status === 'COMPLETED' ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300' :
                        m.status === 'ONGOING'   ? 'bg-amber-500/10 text-amber-700 dark:text-amber-300'    : 'bg-blue-500/10 text-blue-700 dark:text-blue-300'
                      }`}>{m.status}</span>
                    </div>
                    <p className="text-xs text-slate-500 dark:text-zinc-400 mt-1 line-clamp-2">{m.findings}</p>
                    <p className="text-xs text-slate-600 dark:text-zinc-400 mt-0.5">{fmt(m.maintenanceDate)}{m.cost != null ? ` · ${php(m.cost)}` : ''}</p>
                  </div>
                ))
              }
            </div>
          )}

        </div>
      </div>
      </div>

      {showQr && <AssetQrModal asset={asset} onClose={() => setShowQr(false)} />}
      {showEvidence && (
        <EvidenceModal
          path={`/assets/${asset.id}/evidence`}
          title="Asset Evidence"
          subtitle={`${asset.propertyNumber || ''}: ${asset.description || ''}`}
          onClose={() => setShowEvidence(false)}
        />
      )}
    </>
  )
}

const SECTION = 'text-xs font-semibold uppercase tracking-wide text-slate-600 dark:text-zinc-400 mb-0.5'

function Field({ label, value, mono = false }) {
  return (
    <div className="flex items-start gap-2 py-1.5 border-b border-slate-100 dark:border-zinc-800/60 last:border-0">
      <span className="text-xs text-slate-600 dark:text-zinc-400 w-36 flex-shrink-0 pt-0.5">{label}</span>
      <span className={`text-sm text-slate-900 dark:text-zinc-100 font-medium break-words min-w-0 ${mono ? 'font-mono' : ''}`}>{value === '' || value == null ? 'N/A' : value}</span>
    </div>
  )
}

function DrawerAction({ onClick, label, icon, disabled = false }) {
  return (
    <button type="button" onClick={onClick} disabled={disabled}
      className="disabled:opacity-60 flex items-center justify-center gap-1.5 px-2 sm:px-2.5 py-1.5 rounded-md whitespace-nowrap border border-slate-200 dark:border-zinc-700 text-sm font-medium text-slate-700 dark:text-zinc-200 hover:bg-slate-50 dark:hover:bg-zinc-800 transition-colors">
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">{icon}</svg>
      {label}
    </button>
  )
}
