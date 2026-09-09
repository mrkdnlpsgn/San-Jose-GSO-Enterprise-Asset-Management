import { useState, useRef, useCallback } from 'react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import Table from '../../components/common/Table'
import { IMPORT_COLUMNS, downloadImportTemplate, parseImportFile } from './assetExcel'

const REQUIRED_KEYS = ['description', 'categoryName', 'officeName', 'accountablePerson', 'physicalCount', 'acquisitionDate', 'unitValue', 'location', 'condition']

function AssetImportModal({ onClose, onImport }) {
  const [stage, setStage]     = useState('idle') // idle | preview | importing | done
  const [dragOver, setDragOver] = useState(false)
  const [fileName, setFileName] = useState('')
  const [rows, setRows]       = useState([])
  const [error, setError]     = useState('')
  const [saved, setSaved]     = useState([])
  const [failed, setFailed]   = useState([])
  const fileInputRef          = useRef(null)

  const processFile = useCallback((file) => {
    setError('')
    setFileName(file.name)
    parseImportFile(file)
      .then((parsed) => { setRows(parsed); setStage('preview') })
      .catch((err) => setError(err.message))
  }, [])

  const handleDrop = useCallback((e) => {
    e.preventDefault()
    setDragOver(false)
    const file = e.dataTransfer.files[0]
    if (file) processFile(file)
  }, [processFile])

  const handleFileChange = (e) => {
    const file = e.target.files[0]
    if (file) processFile(file)
    e.target.value = ''
  }

  const handleImport = async () => {
    setStage('importing')
    const result = await onImport(rows)
    setSaved(result?.saved ?? [])
    setFailed(result?.failed ?? [])
    setStage('done')
  }

  const reset = () => {
    setStage('idle')
    setRows([])
    setFileName('')
    setError('')
    setSaved([])
    setFailed([])
  }

  const previewCols = IMPORT_COLUMNS.filter((col) => rows.some((r) => r[col.key])).map((c) => ({ key: c.key, label: c.label }))

  // Rows missing a required field — backend will reject these too, but flagging
  // here up front saves a round trip.
  const invalidRowNumbers = rows.reduce((acc, row, i) => {
    if (REQUIRED_KEYS.some((k) => !row[k]?.trim())) acc.push(i + 1)
    return acc
  }, [])

  return (
    <Modal
      title="Bulk Import Assets"
      subtitle={
        stage === 'preview'
          ? `${rows.length} record${rows.length !== 1 ? 's' : ''} detected — review before importing`
          : stage === 'done'
          ? `${saved.length} imported${failed.length > 0 ? `, ${failed.length} failed` : ''}`
          : 'Upload a CSV or XLSX file to create multiple assets at once'
      }
      onClose={onClose}
      size="xl"
    >
      {stage === 'idle' && (
        <div className="space-y-4">
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
                  Category and Office must match existing names exactly (case-insensitive)
                </p>
              </div>
            </div>
            <button
              onClick={downloadImportTemplate}
              className="flex items-center gap-1.5 text-xs font-semibold text-brand-400 hover:text-brand-300 transition-colors duration-150 whitespace-nowrap"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
              assets_import_template.xlsx
            </button>
          </div>

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

          {error && (
            <div className="flex items-start gap-2.5 bg-red-950/50 border border-red-800 text-red-400 rounded-lg px-4 py-3 text-sm">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
              </svg>
              {error}
            </div>
          )}

          <div>
            <p className="text-xs font-semibold text-slate-400 dark:text-zinc-600 uppercase tracking-wider mb-2">Expected Columns</p>
            <div className="flex flex-wrap gap-1.5">
              {IMPORT_COLUMNS.map((col) => (
                <span key={col.key} className="px-2 py-0.5 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 rounded-md text-xs text-slate-500 dark:text-zinc-400">
                  {col.label}
                </span>
              ))}
            </div>
          </div>
        </div>
      )}

      {stage === 'preview' && (
        <div className="space-y-4">
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

          {invalidRowNumbers.length > 0 && (
            <div className="flex items-start gap-3 px-4 py-3 rounded-lg border border-amber-700/40 bg-amber-950/30">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-amber-400 flex-shrink-0 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
              </svg>
              <div>
                <p className="text-sm font-semibold text-amber-300">
                  {invalidRowNumbers.length} row{invalidRowNumbers.length !== 1 ? 's are' : ' is'} missing a required field
                </p>
                <p className="text-xs text-zinc-400 mt-0.5">
                  Row{invalidRowNumbers.length !== 1 ? 's' : ''} {invalidRowNumbers.slice(0, 8).join(', ')}
                  {invalidRowNumbers.length > 8 ? ` and ${invalidRowNumbers.length - 8} more` : ''} will fail — Description,
                  Category, Office, Accountable Person, Qty (Physical Count), Acquisition Date, Unit Value, Location, and
                  Condition are all required.
                </p>
              </div>
            </div>
          )}

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

      {stage === 'importing' && (
        <div className="flex flex-col items-center justify-center py-14 gap-4">
          <svg className="animate-spin h-9 w-9 text-brand-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
          </svg>
          <p className="text-sm text-slate-500 dark:text-zinc-400">Importing {rows.length} records…</p>
        </div>
      )}

      {stage === 'done' && (
        <div className="space-y-4">
          {saved.length > 0 && (
            <div className="flex items-center gap-3 p-4 bg-emerald-950/40 border border-emerald-700/40 rounded-xl">
              <div className="w-9 h-9 rounded-full bg-emerald-950 flex items-center justify-center flex-shrink-0">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-emerald-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-white">
                  {failed.length > 0 ? 'Partially imported' : 'Import successful'}
                </p>
                <p className="text-xs text-slate-300 dark:text-zinc-400 mt-px">
                  {saved.length} asset{saved.length !== 1 ? 's were' : ' was'} created.
                </p>
              </div>
            </div>
          )}

          {failed.length > 0 && (
            <div className="flex items-start gap-3 p-4 bg-red-950/30 border border-red-800/40 rounded-xl">
              <div className="w-8 h-8 rounded-full bg-red-950 flex items-center justify-center flex-shrink-0 mt-0.5">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                </svg>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-white">
                  {failed.length} row{failed.length !== 1 ? 's' : ''} could not be saved
                </p>
                <p className="text-xs text-slate-300 dark:text-zinc-500 mt-0.5 mb-2">
                  These records were not imported. Correct the issues and re-import them.
                </p>
                <div className="space-y-1.5 max-h-40 overflow-y-auto">
                  {failed.map((f, i) => (
                    <div key={i} className="flex items-start gap-2 text-xs">
                      <span className="text-slate-400 dark:text-zinc-400 flex-shrink-0 font-medium truncate max-w-[160px]">
                        {f.row.description || `Row ${i + 1}`}:
                      </span>
                      <span className="text-red-400 leading-snug">{f.reason}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          <div className="flex justify-end pt-2 border-t border-slate-200 dark:border-zinc-800">
            <Button variant="secondary" size="md" onClick={onClose}>Close</Button>
          </div>
        </div>
      )}
    </Modal>
  )
}

export default AssetImportModal
