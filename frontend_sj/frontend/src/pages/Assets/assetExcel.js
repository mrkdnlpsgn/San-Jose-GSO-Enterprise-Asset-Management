import * as XLSX from 'xlsx'

// Import columns — keys must match backend AssetImportRow fields exactly
// (see backend_sj/.../dto/AssetImportRow.java). propertyNumber is deliberately
// excluded: import is create-only, and AssetService auto-generates it.
export const IMPORT_COLUMNS = [
  { key: 'description',       label: 'Description' },
  { key: 'categoryName',      label: 'Category' },
  { key: 'quantity',          label: 'Qty (Property Card)' },
  { key: 'physicalCount',     label: 'Qty (Physical Count)' },
  { key: 'acquisitionDate',   label: 'Acquisition Date' },
  { key: 'unitValue',         label: 'Unit Value' },
  { key: 'officeName',        label: 'Office' },
  { key: 'accountablePerson', label: 'Accountable Person' },
  { key: 'location',          label: 'Location' },
  { key: 'condition',         label: 'Condition' },
  { key: 'remarks',           label: 'Remarks' },
]

// Header text (lowercased) → internal key. Includes the canonical labels above
// plus a few common variants, same tolerance as the existing Equipment import.
const HEADER_MAP = {
  'description':            'description',
  'category':                'categoryName',
  'category name':           'categoryName',
  'qty (property card)':     'quantity',
  'qty property card':       'quantity',
  'quantity':                'quantity',
  'property card qty':       'quantity',
  'qty (physical count)':    'physicalCount',
  'qty physical count':      'physicalCount',
  'physical count':          'physicalCount',
  'acquisition date':        'acquisitionDate',
  'date acquired':           'acquisitionDate',
  'date':                    'acquisitionDate',
  'unit value':              'unitValue',
  'unit value (php)':        'unitValue',
  'amount':                  'unitValue',
  'office':                  'officeName',
  'office name':             'officeName',
  'location (office)':       'officeName',
  'accountable person':      'accountablePerson',
  'location':                'location',
  'physical location':       'location',
  'condition':               'condition',
  'remarks':                 'remarks',
}

const ACCEPTED_EXTENSIONS = ['csv', 'xlsx', 'xls']

export function downloadImportTemplate() {
  const ws = XLSX.utils.aoa_to_sheet([IMPORT_COLUMNS.map((c) => c.label)])
  ws['!cols'] = IMPORT_COLUMNS.map(() => ({ wch: 22 }))
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, 'Assets')
  XLSX.writeFile(wb, 'assets_import_template.xlsx')
}

// Resolves with an array of row objects (string values, matching what the
// backend's AssetImportRow expects), or rejects with a user-facing message.
export function parseImportFile(file) {
  const ext = file.name.split('.').pop().toLowerCase()
  if (!ACCEPTED_EXTENSIONS.includes(ext)) {
    return Promise.reject(new Error('Unsupported file type. Please upload a .csv or .xlsx file.'))
  }

  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = (e) => {
      try {
        const workbook = XLSX.read(e.target.result, { type: 'array' })
        const sheet = workbook.Sheets[workbook.SheetNames[0]]
        const raw = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' })

        if (raw.length < 2) {
          reject(new Error('The file is empty or contains no data rows.'))
          return
        }

        const headers = raw[0].map((h) => String(h).trim().toLowerCase())
        const mappedHeaders = headers.map((h) => HEADER_MAP[h] ?? null)

        if (!mappedHeaders.some(Boolean)) {
          reject(new Error('No recognised columns found. Download the template to see the expected headers.'))
          return
        }

        const parsed = raw
          .slice(1)
          .filter((row) => row.some((cell) => cell !== ''))
          .map((row) => {
            const obj = {}
            mappedHeaders.forEach((key, i) => { if (key) obj[key] = String(row[i] ?? '').trim() })
            return obj
          })

        if (parsed.length === 0) {
          reject(new Error('No data rows found in the file.'))
          return
        }

        resolve(parsed)
      } catch {
        reject(new Error('Failed to read the file. Make sure it is a valid CSV or XLSX.'))
      }
    }
    reader.readAsArrayBuffer(file)
  })
}

// Full-fidelity backup/export — includes the computed shortage/overage columns
// shown in the Assets table, plus fields (accountable person, lifecycle
// status, remarks) not shown there but still worth having in an export.
export function exportAssetsToExcel(assets) {
  const columns = [
    { label: 'Property No.',           value: (a) => a.propertyNumber || '' },
    { label: 'Description',            value: (a) => a.description || '' },
    { label: 'Category',               value: (a) => a.category?.categoryName || '' },
    { label: 'Qty (Property Card)',    value: (a) => a.quantity ?? '' },
    { label: 'Qty (Physical Count)',   value: (a) => a.physicalCount ?? '' },
    { label: 'Shortage/Overage Qty',   value: (a) => (a.physicalCount != null ? a.physicalCount - (a.quantity ?? 0) : '') },
    { label: 'Shortage/Overage Value', value: (a) => (a.physicalCount != null ? (a.physicalCount - (a.quantity ?? 0)) * Number(a.unitValue ?? 0) : '') },
    { label: 'Unit Value',             value: (a) => a.unitValue ?? '' },
    { label: 'Office',                 value: (a) => a.office?.officeName || '' },
    { label: 'Accountable Person',     value: (a) => a.accountablePerson || '' },
    { label: 'Location',               value: (a) => a.location || '' },
    { label: 'Acquisition Date',       value: (a) => a.acquisitionDate || '' },
    { label: 'Condition',              value: (a) => a.condition || '' },
    { label: 'Lifecycle Status',       value: (a) => a.lifecycleStatus || '' },
    { label: 'Remarks',                value: (a) => a.remarks || '' },
  ]

  const aoa = [columns.map((c) => c.label), ...assets.map((a) => columns.map((c) => c.value(a)))]
  const ws = XLSX.utils.aoa_to_sheet(aoa)
  ws['!cols'] = columns.map(() => ({ wch: 20 }))
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, 'Assets')

  const stamp = new Date().toISOString().slice(0, 10)
  XLSX.writeFile(wb, `assets_export_${stamp}.xlsx`)
}
