import { useState, useRef, useCallback } from 'react'
import * as XLSX from 'xlsx'
import { QRCodeSVG } from 'qrcode.react'
import Modal from './Modal'
import Button from './Button'
import { escapeHtml } from '../../utils/helpers'
import Table from './Table'

const QR_PREFIX = 'ict-inv:'

// ── Print utilities ───────────────────────────────────────────────────────────
function buildPrintCard(item, svgHTML) {
  const loc = [item.office, item.location].filter(Boolean).map(escapeHtml).join(' · ')
  return `
    <div class="card">
      ${svgHTML}
      <p class="title">${escapeHtml(item.article) || '—'}</p>
      <p class="sub">${escapeHtml(item.equipmentType) || ''}</p>
      <p class="sub">${loc}</p>
      <span class="badge">${escapeHtml(item.itemCode) || ''}</span>
      <p class="org">San Jose Municipal Hall · GSO Inventory Management System</p>
    </div>`
}

const PRINT_STYLES = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #fff; }
  .card { border: 1.5px solid #e5e7eb; border-radius: 10px; padding: 14px 12px; text-align: center; break-inside: avoid; }
  .card svg { display: block; margin: 0 auto 8px; }
  .title { font-size: 12px; font-weight: 700; color: #111; margin-bottom: 2px; }
  .sub   { font-size: 10px; color: #6b7280; margin-bottom: 1px; }
  .badge { display: inline-block; margin-top: 6px; padding: 2px 8px; background: #f3f4f6; border-radius: 99px; font-size: 10px; font-weight: 600; color: #374151; }
  .org   { margin-top: 8px; padding-top: 6px; border-top: 1px solid #f3f4f6; font-size: 9px; color: #9ca3af; }
`

function printSingleQR(item) {
  const svgEl = document.getElementById(`qr-import-${item.id}`)
  if (!svgEl) return
  const win = window.open('', '_blank', 'width=480,height=640')
  win.document.write(`<!DOCTYPE html><html><head><title>QR Code</title>
    <style>${PRINT_STYLES} body { display:flex; align-items:center; justify-content:center; min-height:100vh; padding:24px; } .card { max-width:280px; width:100%; border-width:2px; padding:24px 28px; }</style>
  </head><body>${buildPrintCard(item, svgEl.outerHTML)}
  <script>window.onload=()=>{window.print();window.onafterprint=()=>window.close()}<\/script></body></html>`)
  win.document.close()
}

function printAllQRCodes(savedItems) {
  const cards = savedItems.map((item) => {
    const svgEl = document.getElementById(`qr-import-${item.id}`)
    return svgEl ? buildPrintCard(item, svgEl.outerHTML) : null
  }).filter(Boolean)
  if (!cards.length) return

  const win = window.open('', '_blank', 'width=900,height=700')
  win.document.write(`<!DOCTYPE html><html><head><title>QR Codes</title>
    <style>${PRINT_STYLES}
      body { padding: 20px; }
      h1 { font-size: 13px; font-weight: 700; margin-bottom: 14px; color: #111; }
      .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
      @media print { @page { margin: 10mm; } body { padding: 0; } }
    </style>
  </head><body>
    <h1>GSO Inventory QR Codes — San Jose Municipal Hall (${cards.length} record${cards.length !== 1 ? 's' : ''})</h1>
    <div class="grid">${cards.join('')}</div>
    <script>window.onload=()=>{window.print();window.onafterprint=()=>window.close()}<\/script>
  </body></html>`)
  win.document.close()
}

// Expected unified inventory + device columns
const COLUMNS = [
  { key: 'type',              label: 'Type' },
  { key: 'equipmentType',     label: 'Type of Equipment' },
  { key: 'itemCode',          label: 'Item Code' },
  { key: 'article',           label: 'Article' },
  { key: 'model',             label: 'Model' },
  { key: 'serialNumber',      label: 'Serial Number' },
  { key: 'amountValue',       label: 'Amount Value' },
  { key: 'acquisitionDate',   label: 'Acquisition Date' },
  { key: 'office',            label: 'Office' },
  { key: 'location',          label: 'Location' },
  { key: 'description',       label: 'Description' },
  { key: 'accountablePerson',      label: 'Accountable Person' },
  { key: 'accountablePersonEmail', label: 'Contact Email' },
  { key: 'accountablePersonPhone', label: 'Contact Number' },
]

// Map spreadsheet header text → internal key (case-insensitive, trimmed)
const HEADER_MAP = {
  'type':                 'type',
  'type of equipment':    'equipmentType',
  'equipmenttype':        'equipmentType',
  'item code':            'itemCode',
  'itemcode':             'itemCode',
  'article':              'article',
  'model':                'model',
  'serial number':        'serialNumber',
  'serialnumber':         'serialNumber',
  'serial no':            'serialNumber',
  'serial no.':           'serialNumber',
  'amount value':         'amountValue',
  'amountvalue':          'amountValue',
  'amount':               'amountValue',
  'acquisition date':     'acquisitionDate',
  'acquisitiondate':      'acquisitionDate',
  'date acquired':        'acquisitionDate',
  'office':               'office',
  'location':             'location',
  'description':          'description',
  'accountable person':        'accountablePerson',
  'accountableperson':         'accountablePerson',
  'contact email':             'accountablePersonEmail',
  'contactemail':              'accountablePersonEmail',
  'email':                     'accountablePersonEmail',
  'accountablepersonemail':    'accountablePersonEmail',
  'contact number':            'accountablePersonPhone',
  'contactnumber':             'accountablePersonPhone',
  'phone':                     'accountablePersonPhone',
  'phone number':              'accountablePersonPhone',
  'mobile':                    'accountablePersonPhone',
  'mobile number':             'accountablePersonPhone',
  'accountablepersonphone':    'accountablePersonPhone',
}

const ACCEPTED_EXTENSIONS = ['csv', 'xlsx', 'xls']

function ImportModal({ onClose, onImport }) {
  const [stage, setStage]           = useState('idle') // idle | preview | importing | done
  const [dragOver, setDragOver]     = useState(false)
  const [fileName, setFileName]     = useState('')
  const [rows, setRows]             = useState([])
  const [error, setError]           = useState('')
  const [savedItems, setSavedItems] = useState([])
  const [failedItems, setFailedItems] = useState([])
  const fileInputRef                = useRef(null)

  // ── File parsing ──────────────────────────────────────────────────────────
  const processFile = useCallback((file) => {
    const ext = file.name.split('.').pop().toLowerCase()
    if (!ACCEPTED_EXTENSIONS.includes(ext)) {
      setError('Unsupported file type. Please upload a .csv or .xlsx file.')
      return
    }

    setError('')
    setFileName(file.name)

    const reader = new FileReader()
    reader.onload = (e) => {
      try {
        const workbook = XLSX.read(e.target.result, { type: 'array' })
        const sheet    = workbook.Sheets[workbook.SheetNames[0]]
        const raw      = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' })

        if (raw.length < 2) {
          setError('The file is empty or contains no data rows.')
          return
        }

        const headers       = raw[0].map((h) => String(h).trim().toLowerCase())
        const mappedHeaders = headers.map((h) => HEADER_MAP[h] ?? null)

        const hasAnyKnownCol = mappedHeaders.some(Boolean)
        if (!hasAnyKnownCol) {
          setError(
            'No recognised columns found. Download the template to see the expected headers.'
          )
          return
        }

        const parsed = raw
          .slice(1)
          .filter((row) => row.some((cell) => cell !== ''))
          .map((row) => {
            const obj = {}
            mappedHeaders.forEach((key, i) => {
              if (key) obj[key] = String(row[i] ?? '').trim()
            })
            return obj
          })

        if (parsed.length === 0) {
          setError('No data rows found in the file.')
          return
        }

        setRows(parsed)
        setStage('preview')
      } catch {
        setError('Failed to read the file. Make sure it is a valid CSV or XLSX.')
      }
    }
    reader.readAsArrayBuffer(file)
  }, [])

  // ── Event handlers ────────────────────────────────────────────────────────
  const handleDrop = useCallback(
    (e) => {
      e.preventDefault()
      setDragOver(false)
      const file = e.dataTransfer.files[0]
      if (file) processFile(file)
    },
    [processFile]
  )

  const handleFileChange = (e) => {
    const file = e.target.files[0]
    if (file) processFile(file)
    e.target.value = ''
  }

  const handleImport = async () => {
    setStage('importing')
    const result = await onImport(rows)
    const saved  = result?.saved  ?? (Array.isArray(result) ? result : [])
    const failed = result?.failed ?? []
    setSavedItems(saved)
    setFailedItems(failed)
    setStage('done')
  }

  const reset = () => {
    setStage('idle')
    setRows([])
    setFileName('')
    setError('')
    setSavedItems([])
    setFailedItems([])
  }

  // ── Template download ─────────────────────────────────────────────────────
  const downloadTemplate = () => {
    const ws = XLSX.utils.aoa_to_sheet([COLUMNS.map((c) => c.label)])
    // Style header row width
    ws['!cols'] = COLUMNS.map(() => ({ wch: 22 }))
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, ws, 'Inventory')
    XLSX.writeFile(wb, 'inventory_template.xlsx')
  }

  // Only show columns that actually have data in the preview
  const previewCols = COLUMNS.filter((col) => rows.some((r) => r[col.key]))

  // Pre-import validation: flag rows missing the required Article field
  const rowsWithoutArticle = rows.reduce((acc, row, i) => {
    if (!row.article?.trim()) acc.push(i + 1)
    return acc
  }, [])

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <Modal
      title="Bulk Import Inventory"
      subtitle={
        stage === 'preview'
          ? `${rows.length} record${rows.length !== 1 ? 's' : ''} detected — review before importing`
          : stage === 'done' && failedItems.length > 0
          ? `${savedItems.length} imported, ${failedItems.length} failed — review the summary below`
          : stage === 'done'
          ? `${savedItems.length} record${savedItems.length !== 1 ? 's' : ''} imported — QR codes ready to print`
          : 'Upload a CSV or XLSX file to import multiple records at once'
      }
      onClose={onClose}
      size="xl"
    >
      {/* ── STAGE: idle ─────────────────────────────────────────────────── */}
      {stage === 'idle' && (
        <div className="space-y-4">
          {/* Template download banner */}
          <div className="flex items-center justify-between p-3.5 bg-slate-50 dark:bg-zinc-800 rounded-lg border border-slate-200 dark:border-zinc-700">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-lg bg-emerald-950 flex items-center justify-center flex-shrink-0">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-emerald-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
                </svg>
              </div>
              <div>
                <p className="text-sm font-medium text-slate-800 dark:text-zinc-200">Download Import Template</p>
                <p className="text-xs text-slate-500 dark:text-zinc-500 mt-px">
                  Use this template to ensure your file has the correct column headers
                </p>
              </div>
            </div>
            <button
              onClick={downloadTemplate}
              className="flex items-center gap-1.5 text-xs font-semibold text-brand-400 hover:text-brand-300 transition-colors duration-150 whitespace-nowrap"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
              inventory_template.xlsx
            </button>
          </div>

          {/* Drag & drop zone */}
          <div
            onDragOver={(e) => { e.preventDefault(); setDragOver(true) }}
            onDragLeave={() => setDragOver(false)}
            onDrop={handleDrop}
            onClick={() => fileInputRef.current?.click()}
            className={`
              relative border-2 border-dashed rounded-xl px-6 py-12 text-center cursor-pointer
              transition-all duration-200 select-none
              ${dragOver
                ? 'border-brand-500 bg-brand-500/5'
                : 'border-slate-200 dark:border-zinc-700 hover:border-slate-300 dark:hover:border-zinc-500 bg-slate-50 dark:bg-zinc-900/40 hover:bg-slate-100 dark:hover:bg-zinc-900/70'
              }
            `}
          >
            <div className="flex flex-col items-center gap-3">
              <div className={`w-14 h-14 rounded-2xl flex items-center justify-center transition-colors duration-200 ${dragOver ? 'bg-brand-500/20' : 'bg-slate-100 dark:bg-zinc-800'}`}>
                <svg xmlns="http://www.w3.org/2000/svg" className={`h-7 w-7 transition-colors duration-200 ${dragOver ? 'text-brand-400' : 'text-slate-400 dark:text-zinc-500'}`} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
                </svg>
              </div>
              <div>
                <p className={`text-sm font-semibold transition-colors duration-200 ${dragOver ? 'text-brand-400' : 'text-slate-700 dark:text-zinc-300'}`}>
                  {dragOver ? 'Release to upload' : 'Drag & drop your file here'}
                </p>
                <p className="text-xs text-slate-500 dark:text-zinc-600 mt-1">
                  or <span className="text-brand-400 font-medium">click to browse</span>
                </p>
              </div>
              <div className="flex items-center gap-2 mt-1">
                {['.csv', '.xlsx'].map((ext) => (
                  <span key={ext} className="px-2 py-0.5 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 rounded text-2xs font-medium text-slate-500 dark:text-zinc-400">
                    {ext}
                  </span>
                ))}
              </div>
            </div>
            <input
              ref={fileInputRef}
              type="file"
              accept=".csv,.xlsx,.xls"
              className="hidden"
              onChange={handleFileChange}
            />
          </div>

          {/* Error */}
          {error && (
            <div className="flex items-start gap-2.5 bg-red-950/50 border border-red-800 text-red-400 rounded-lg px-4 py-3 text-sm">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
              </svg>
              {error}
            </div>
          )}

          {/* Expected columns hint */}
          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-wider mb-2">Expected Columns</p>
            <div className="flex flex-wrap gap-1.5">
              {COLUMNS.map((col) => (
                <span key={col.key} className="px-2 py-0.5 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 rounded-md text-xs text-slate-500 dark:text-zinc-400">
                  {col.label}
                </span>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ── STAGE: preview ──────────────────────────────────────────────── */}
      {stage === 'preview' && (
        <div className="space-y-4">
          {/* File info bar */}
          <div className="flex items-center justify-between p-3.5 bg-slate-50 dark:bg-zinc-800 rounded-lg border border-slate-200 dark:border-zinc-700">
            <div className="flex items-center gap-3 min-w-0">
              <div className="w-9 h-9 rounded-lg bg-slate-200 dark:bg-zinc-700 flex items-center justify-center flex-shrink-0">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-slate-500 dark:text-zinc-300" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z" clipRule="evenodd" />
                </svg>
              </div>
              <div className="min-w-0">
                <p className="text-sm font-medium text-slate-800 dark:text-zinc-200 truncate">{fileName}</p>
                <p className="text-xs text-slate-500 dark:text-zinc-500 mt-px">
                  <span className="text-emerald-400 font-semibold">{rows.length}</span> record{rows.length !== 1 ? 's' : ''} ready to import
                </p>
              </div>
            </div>
            <button
              onClick={reset}
              className="text-xs text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-300 transition-colors duration-150 whitespace-nowrap ml-4"
            >
              Change file
            </button>
          </div>

          {/* Validation warning */}
          {rowsWithoutArticle.length > 0 && (
            <div className="flex items-start gap-3 px-4 py-3 rounded-lg border border-amber-700/40 bg-amber-950/30">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-amber-400 flex-shrink-0 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
              </svg>
              <div>
                <p className="text-sm font-semibold text-amber-300">
                  {rowsWithoutArticle.length} row{rowsWithoutArticle.length !== 1 ? 's are' : ' is'} missing a required field
                </p>
                <p className="text-xs text-zinc-400 mt-0.5">
                  <span className="font-medium">Article</span> is required. Row{rowsWithoutArticle.length !== 1 ? 's' : ''}{' '}
                  {rowsWithoutArticle.slice(0, 5).join(', ')}
                  {rowsWithoutArticle.length > 5 ? ` and ${rowsWithoutArticle.length - 5} more` : ''}{' '}
                  will be skipped. Fix the file and re-upload to import all rows.
                </p>
              </div>
            </div>
          )}

          {/* Preview table */}
          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-wider mb-2">
              Preview — first {Math.min(rows.length, 5)} of {rows.length} row{rows.length !== 1 ? 's' : ''}
            </p>
            <Table columns={previewCols} data={rows.slice(0, 5)} />
            {rows.length > 5 && (
              <p className="text-xs text-slate-400 dark:text-zinc-600 mt-2 text-center">
                +{rows.length - 5} more record{rows.length - 5 !== 1 ? 's' : ''} not shown
              </p>
            )}
          </div>

          {/* Action bar */}
          <div className="flex items-center justify-between pt-3 border-t border-slate-200 dark:border-zinc-800">
            <button
              onClick={reset}
              className="flex items-center gap-1.5 text-sm text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-300 transition-colors duration-150"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clipRule="evenodd" />
              </svg>
              Back
            </button>
            <div className="flex gap-2">
              <Button variant="secondary" size="md" onClick={onClose}>Cancel</Button>
              <Button variant="primary" size="md" onClick={handleImport}>
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM6.293 9.293a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
                </svg>
                Import {rows.length} Record{rows.length !== 1 ? 's' : ''}
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* ── STAGE: importing ────────────────────────────────────────────── */}
      {stage === 'importing' && (
        <div className="flex flex-col items-center justify-center py-14 gap-4">
          <svg className="animate-spin h-9 w-9 text-brand-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
          </svg>
          <p className="text-sm text-slate-500 dark:text-zinc-400">Importing {rows.length} records…</p>
        </div>
      )}

      {/* ── STAGE: done — QR codes ──────────────────────────────────────── */}
      {stage === 'done' && (
        <div className="space-y-4">
          {/* Success / partial banner */}
          {savedItems.length > 0 && (
          <div className="flex items-center gap-3 p-4 bg-emerald-950/40 border border-emerald-700/40 rounded-xl">
            <div className="w-9 h-9 rounded-full bg-emerald-950 flex items-center justify-center flex-shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-emerald-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
              </svg>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-white">
                {failedItems.length > 0 ? 'Partially imported' : 'Import successful'}
              </p>
              <p className="text-xs text-slate-300 dark:text-zinc-400 mt-px">
                {savedItems.length} record{savedItems.length !== 1 ? 's were' : ' was'} added to inventory.
              </p>
            </div>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => printAllQRCodes(savedItems)}
              className="flex-shrink-0"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5 mr-1" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
              </svg>
              Print All QR Codes
            </Button>
          </div>
          )}

          {/* Failure summary */}
          {failedItems.length > 0 && (
            <div className="flex items-start gap-3 p-4 bg-red-950/30 border border-red-800/40 rounded-xl">
              <div className="w-8 h-8 rounded-full bg-red-950 flex items-center justify-center flex-shrink-0 mt-0.5">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                </svg>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-white">
                  {failedItems.length} row{failedItems.length !== 1 ? 's' : ''} could not be saved
                </p>
                <p className="text-xs text-slate-300 dark:text-zinc-500 mt-0.5 mb-2">
                  These records were not imported. Correct the issues and re-import them.
                </p>
                <div className="space-y-1.5 max-h-28 overflow-y-auto">
                  {failedItems.map((f, i) => (
                    <div key={i} className="flex items-start gap-2 text-xs">
                      <span className="text-slate-400 dark:text-zinc-400 flex-shrink-0 font-medium truncate max-w-[8.75rem]">
                        {f.row.article || f.row.itemCode || `Row ${i + 1}`}:
                      </span>
                      <span className="text-red-400 leading-snug">{f.reason}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* QR code grid */}
          {savedItems.length > 0 && (
          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider mb-2.5">
              QR Codes — {savedItems.length} record{savedItems.length !== 1 ? 's' : ''}
            </p>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 max-h-[360px] overflow-y-auto pr-1">
              {savedItems.map((item) => (
                <div
                  key={item.id}
                  className="bg-white rounded-xl p-3 flex flex-col items-center gap-1.5 shadow-sm"
                >
                  <QRCodeSVG
                    id={`qr-import-${item.id}`}
                    value={`${QR_PREFIX}${item.id}`}
                    size={88}
                    bgColor="#ffffff"
                    fgColor="#111827"
                    level="H"
                  />
                  <p className="text-2xs font-semibold text-gray-900 leading-tight text-center w-full truncate">
                    {item.article || '—'}
                  </p>
                  {item.itemCode && (
                    <span className="text-[0.625rem] bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full font-medium">
                      {item.itemCode}
                    </span>
                  )}
                  <button
                    onClick={() => printSingleQR(item)}
                    className="flex items-center gap-1 text-[0.625rem] font-semibold text-brand-600 hover:text-brand-500 transition-colors mt-0.5"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
                    </svg>
                    Print
                  </button>
                </div>
              ))}
            </div>
          </div>
          )}

          {/* Footer */}
          <div className="flex justify-end pt-2 border-t border-slate-200 dark:border-zinc-800">
            <Button variant="secondary" size="md" onClick={onClose}>Close</Button>
          </div>
        </div>
      )}
    </Modal>
  )
}

export default ImportModal
