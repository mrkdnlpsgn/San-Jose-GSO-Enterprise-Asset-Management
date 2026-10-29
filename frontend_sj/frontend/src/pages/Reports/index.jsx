import { useState, useRef, useMemo, useEffect } from 'react'
import { useLocation } from 'react-router-dom'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import DatePicker from '../../components/common/DatePicker'
import { useToast } from '../../context/ToastContext'
import { manilaDateKey } from '../../utils/helpers'
import api from '../../services/api'
import { getPropertyCards } from '../../services/propertyCardService'
import { getReplacementForecast, getDepreciation, getMaintenanceForecast } from '../../services/aiRecommendationService'
import { printPropertyCards, exportPropertyCardsExcel } from '../../utils/propertyCardExport'
import { openPrintWindow } from '../../utils/printWindow'
import { printForm, toPages, longDate } from '../../utils/printForm'
import { printRpcppe, exportRpcppeExcel, rpcppeRows, rpcppeLine, RPCPPE_DEFAULTS } from '../../utils/rpcppeExport'
import { maintenanceCardsOf, cardLines, printMaintenanceCards, exportMaintenanceCardsExcel } from '../../utils/maintenanceCardPrint'
import { LazyFooter, useLazyRows } from '../../components/common/ListKit'

// Reports need the full dataset, not a paginated page. getAssets()/getDisposal()/getMaintenance()
// default to the backend's page size of 20 - fine for list pages, wrong here, so fetch directly
// with a size large enough to always cover a single municipal office's inventory in one page.
const getAllAssets     = () => api.get('/assets', { params: { size: 100000 } })
const getAllDisposal   = () => api.get('/disposal', { params: { size: 100000 } })
const getAllMaintenance = () => api.get('/maintenance', { params: { size: 100000 } })

// ── Formatters ────────────────────────────────────────────────────────────────
const fmtDate = (d) =>
  d ? new Date(d).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' }) : 'N/A'
const fmtMoney = (v) =>
  v != null && v !== '' ? '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 }) : 'N/A'
const fmtDateTime = (dt) =>
  dt ? new Date(dt).toLocaleString('en-PH', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : 'N/A'
const esc = (s) => String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

// ── Date filtering ────────────────────────────────────────────────────────────
// With thousands of assets, reports default to unbounded - this lets a user
// scope a report down to a specific day/week/month/year (or a custom range)
// before previewing or exporting it.
const localDateStr = (d) => {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

const DATE_PRESETS = [
  { key: 'day',   label: 'Today' },
  { key: 'week',  label: 'This Week' },
  { key: 'month', label: 'This Month' },
  { key: 'year',  label: 'This Year' },
]

function presetRange(preset) {
  const now = new Date()
  const to = localDateStr(now)
  if (preset === 'day') return { from: to, to }
  if (preset === 'week') {
    const d = new Date(now)
    d.setDate(d.getDate() - 6)
    return { from: localDateStr(d), to }
  }
  if (preset === 'month') return { from: localDateStr(new Date(now.getFullYear(), now.getMonth(), 1)), to }
  if (preset === 'year') return { from: localDateStr(new Date(now.getFullYear(), 0, 1)), to }
  return { from: '', to: '' }
}

function applyDateFilter(rows, dateField, from, to) {
  if (!dateField || (!from && !to)) return rows
  return rows.filter((r) => {
    const v = r[dateField]
    if (!v) return false
    const d = manilaDateKey(v)
    if (from && d < from) return false
    if (to && d > to) return false
    return true
  })
}

// PAR numbers are compared trimmed and case-insensitive, matching how the Assets search treats them.
const normPar = (v) => String(v || '').trim().toUpperCase()
const lineAmount = (r) => (Number(r.unitValue) || 0) * (Number(r.quantity) || 1)
const uniqueJoined = (rows, pick) => [...new Set(rows.map(pick).filter(Boolean))].join(', ')

// ── Report definitions ────────────────────────────────────────────────────────
// PAR items: the PAR report's columns, also listed under an expanded PAR row.
const PAR_HEADERS = [
  { label: 'Qty',            display: (r) => r.quantity ?? 1,                                                                                        raw: (r) => r.quantity ?? 1 },
  { label: 'Description',    display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.description || 'N/A'}</span>,              raw: (r) => r.description || '' },
  { label: 'Serial No.',     display: (r) => <span className="font-mono text-xs">{r.serialNumber || 'N/A'}</span>,                                     raw: (r) => r.serialNumber || '' },
  { label: 'Property No.',   display: (r) => <span className="font-mono text-xs">{r.propertyNumber || 'N/A'}</span>,                                   raw: (r) => r.propertyNumber || '' },
  { label: 'Date Acquired',  display: (r) => fmtDate(r.acquisitionDate),                                                                             raw: (r) => r.acquisitionDate || '' },
  { label: 'Unit Cost',      display: (r) => fmtMoney(r.unitValue),                                                                                  raw: (r) => r.unitValue != null ? Number(r.unitValue).toFixed(2) : '' },
  { label: 'Amount',         display: (r) => fmtMoney(lineAmount(r)),                                                                                raw: (r) => lineAmount(r).toFixed(2) },
]

// One RPCPPE line, as listed under an expanded type of PPE (same columns as the printed form).
const RPCPPE_HEADERS = [
  { label: 'Article',          display: (a) => rpcppeLine(a).article || 'N/A' },
  { label: 'Location',         display: (a) => rpcppeLine(a).location || 'N/A' },
  { label: 'Description',      display: (a) => <span className="font-medium text-slate-900 dark:text-white">{rpcppeLine(a).description || 'N/A'}</span> },
  { label: 'Property No.',     display: (a) => <span className="font-mono">{rpcppeLine(a).propertyNumber || 'N/A'}</span> },
  { label: 'Unit',             display: () => 'unit' },
  { label: 'Unit Value',       display: (a) => fmtMoney(a.unitValue) },
  { label: 'Qty (Card)',       display: (a) => rpcppeLine(a).qtyCard },
  { label: 'Qty (Count)',      display: (a) => rpcppeLine(a).qtyCount },
  { label: 'Shortage/Overage', display: (a) => { const l = rpcppeLine(a); return l.soQty === '' ? '' : `${l.soQty} · ${fmtMoney(l.soValue)}` } },
  { label: 'Remarks',          display: (a) => <span className="italic">{rpcppeLine(a).remarks}</span> },
]

// One RPCPPE form per type of PPE (category), with the items on hand as at the report date.
// A Repair and Maintenance Card's columns, for the preview under each picked asset
const MAINTENANCE_CARD_HEADERS = [
  { label: 'Date of Repair', display: (l) => l.date },
  { label: 'Particular',     display: (l) => (l.kind === 'repair' ? <span className="font-medium text-slate-900 dark:text-white">{l.particular}</span>
    : <span className={`pl-3 ${l.kind === 'laborHead' ? 'italic' : ''}`}>{l.particular}</span>) },
  { label: 'Unit',           display: (l) => l.unit },
  { label: 'Quantity',       display: (l) => l.quantity },
  { label: 'Unit Cost',      display: (l) => l.unitCost },
  { label: 'Total Cost',     display: (l) => l.total },
  { label: 'Cost of Repair', display: (l) => (l.cost ? <span className="font-semibold">{l.cost}</span> : '') },
]

function rpcppeGroupsOf(assets, settings) {
  const byCat = new Map()
  rpcppeRows(assets, settings?.asAt).forEach((a) => {
    const key = String(a.category?.id ?? 'none')
    if (!byCat.has(key)) byCat.set(key, { key, categoryName: a.category?.categoryName || 'Uncategorized', rows: [] })
    byCat.get(key).rows.push(a)
  })
  return [...byCat.values()]
    .map((g) => ({ ...g, total: g.rows.reduce((n, a) => n + lineAmount(a), 0) }))
    .sort((a, b) => a.categoryName.localeCompare(b.categoryName))
}

// One Property Card line, as listed under an expanded card row.
const CARD_ENTRY_HEADERS = [
  { label: 'Date',                 display: (e) => fmtDate(e.date) },
  { label: 'Reference Property #', display: (e) => <span className="font-mono">{e.reference || 'N/A'}</span> },
  { label: 'Description',          display: (e) => e.description || 'N/A' },
  { label: 'Receipt Qty',          display: (e) => e.receiptQty ?? '' },
  { label: 'Transfer',             display: (e) => e.transferTo || 'N/A' },
  { label: 'Office',               display: (e) => e.office || 'N/A' },
  { label: 'Balance Qty',          display: (e) => e.balanceQty },
]

// One entry per distinct PAR number in the loaded assets, newest PAR first
// (PAR numbers start with the acquisition year-month).
function parGroupsOf(assets) {
  const byKey = new Map()
  assets.forEach((a) => {
    const key = normPar(a.parNumber)
    if (!key) return
    if (!byKey.has(key)) byKey.set(key, { key, par: a.parNumber.trim(), rows: [] })
    byKey.get(key).rows.push(a)
  })
  return [...byKey.values()]
    .map((g) => ({ ...g, ...parHeader(g.rows, g.par), office: uniqueJoined(g.rows, (r) => r.office?.officeName) }))
    .sort((a, b) => b.par.localeCompare(a.par))
}

// Repairs & Maintenance Forecast columns: the 3 full years before this one, this year so far, and
// next year's estimate (the same years MaintenanceForecastService uses, in Manila time).
const FORECAST_YEAR = Number(manilaDateKey(new Date().toISOString()).slice(0, 4)) + 1
const FORECAST_HISTORY = [FORECAST_YEAR - 4, FORECAST_YEAR - 3, FORECAST_YEAR - 2, FORECAST_YEAR - 1].map(String)
const TREND_LABEL = { RISING: 'Rising', FALLING: 'Falling', STEADY: 'Steady' }

const REPORTS = [
  {
    id: 'rpcppe',
    title: 'RPCPPE (Physical Count)',
    description: 'Report on the Physical Count of Property, Plant and Equipment: one form per type of PPE, in the GSO\'s printed format.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path d="M9 2a1 1 0 000 2h2a1 1 0 100-2H9z" />
        <path fillRule="evenodd" d="M4 5a2 2 0 012-2 3 3 0 003 3h2a3 3 0 003-3 2 2 0 012 2v11a2 2 0 01-2 2H6a2 2 0 01-2-2V5zm3 4a1 1 0 000 2h.01a1 1 0 100-2H7zm3 0a1 1 0 000 2h3a1 1 0 100-2h-3zm-3 4a1 1 0 100 2h.01a1 1 0 100-2H7zm3 0a1 1 0 100 2h3a1 1 0 100-2h-3z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getAllAssets()).data
    },
    // The report header (as-at date, fund cluster, accountable officer) is filled in above the list.
    rpcppeSettings: true,
    selectable: {
      toItems: rpcppeGroupsOf,
      noun: ['type of PPE', 'types of PPE'],
      placeholder: 'Search type, article, office, property No.',
      hint: 'Tick one or more types of PPE to export their physical count reports.',
      none: 'No assets on hand as at this date.',
      search: (g, q) => g.categoryName.toLowerCase().includes(q)
        || g.rows.some((a) => [a.article?.articleName, a.office?.officeName, a.propertyNumber, a.description]
          .some((v) => String(v || '').toLowerCase().includes(q))),
      label: (g) => g.categoryName,
      columns: [
        { label: 'Type of PPE', cell: (g) => <span className="font-medium text-slate-900 dark:text-white">{g.categoryName}</span> },
        { label: 'Items',       cell: (g) => g.rows.length.toLocaleString('en-PH'), right: true },
        { label: 'Total Value', cell: (g) => fmtMoney(g.total), right: true },
      ],
      expandLabel: 'items',
      expanded: (g) => <MiniTable headers={RPCPPE_HEADERS} rows={g.rows} rowKey={(a) => a.id} />,
      summary: (items) => `${items.reduce((n, g) => n + g.rows.length, 0).toLocaleString('en-PH')} items · Total ${fmtMoney(items.reduce((n, g) => n + g.total, 0))}`,
      exportExcel: (items, settings) => exportRpcppeExcel(items, settings),
      exportPdf: (items, settings) => printRpcppe(items, settings),
    },
    headers: [],
  },
  {
    id: 'condition',
    title: 'Condition Report',
    printTitle: 'REPORT ON THE CONDITION OF PROPERTY, PLANT AND EQUIPMENT',
    description: 'Asset breakdown by condition: new, good, serviceable, repairable, and unserviceable counts.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getAllAssets()).data
    },
    // Aggregation runs after the date filter (see `transform`), on whichever
    // assets fall inside the selected acquisitionDate range. `aggregated: true`
    // tells the preview not to show a "(of N raw rows)" count, since row count
    // here is condition groups, not filtered records.
    dateField: 'acquisitionDate',
    aggregated: true,
    transform(assets) {
      const map = {}
      assets.forEach((a) => {
        const key = a.condition || 'UNKNOWN'
        if (!map[key]) map[key] = { condition: key, count: 0, totalValue: 0, offices: new Set() }
        map[key].count++
        map[key].totalValue += (Number(a.unitValue) || 0) * (Number(a.quantity) || 1)
        if (a.office?.officeName) map[key].offices.add(a.office.officeName)
      })
      return Object.values(map)
        .sort((a, b) => b.count - a.count)
        .map((r) => ({ ...r, offices: [...r.offices].join(', ') || 'N/A' }))
    },
    headers: [
      { label: 'Condition',       display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.condition}</span>,                      raw: (r) => r.condition },
      { label: 'Count',           display: (r) => <span className="font-semibold text-brand-400">{r.count}</span>,                                        raw: (r) => r.count },
      { label: 'Total Value (₱)', display: (r) => r.totalValue > 0 ? fmtMoney(r.totalValue) : 'N/A',                                                       raw: (r) => r.totalValue > 0 ? r.totalValue.toFixed(2) : '' },
      { label: 'Offices',         display: (r) => <span className="text-slate-400 dark:text-zinc-400 text-xs">{r.offices}</span>,                         raw: (r) => r.offices },
    ],
    certification: [
      { label: 'Prepared by:', caption: 'Signature over Printed Name of Property Custodian / GSO Staff' },
      { label: 'Approved by:', caption: 'Signature over Printed Name of Municipal General Services Officer' },
    ],
  },
  {
    id: 'replacement',
    title: 'Replacement Forecast',
    printTitle: 'REPLACEMENT FORECAST OF PROPERTY, PLANT AND EQUIPMENT',
    certification: [
      { label: 'Prepared by:', caption: 'Signature over Printed Name of Property Custodian / GSO Staff' },
      { label: 'Approved by:', caption: 'Signature over Printed Name of Municipal General Services Officer' },
    ],
    description: 'Assets due for replacement now and in the next 3 years, with the estimated cost, for budget planning.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M6 2a1 1 0 00-1 1v1H4a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2h-1V3a1 1 0 10-2 0v1H7V3a1 1 0 00-1-1zm0 5a1 1 0 000 2h8a1 1 0 100-2H6z" clipRule="evenodd" />
      </svg>
    ),
    // Same settings as the Home card, so the totals match it.
    async load() {
      return (await getReplacementForecast({ years: 3, priceIncrease: 3, items: true })).data.items
    },
    dateField: 'endOfLife',
    extraRows: (rows) => [
      ...rows,
      {
        replaceIn: '', propertyNumber: 'TOTAL ESTIMATED COST', description: `${rows.length} assets`, category: '', office: '',
        acquisitionDate: '', usefulLifeYears: '', endOfLife: '', reason: '', condition: '', unitValue: null,
        estimatedCost: rows.reduce((s, r) => s + (Number(r.estimatedCost) || 0), 0),
      },
    ],
    headers: [
      { label: 'Replace In',      display: (r) => <span className={r.replaceIn === 'NOW' ? 'font-semibold text-amber-700 dark:text-amber-300' : ''}>{r.replaceIn === 'NOW' ? 'Now' : r.replaceIn}</span>, raw: (r) => r.replaceIn === 'NOW' ? 'Now' : r.replaceIn },
      { label: 'Property No.',    display: (r) => <span className="font-mono text-xs">{r.propertyNumber || 'N/A'}</span>,                                   raw: (r) => r.propertyNumber || '' },
      { label: 'Description',     display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.description || 'N/A'}</span>,              raw: (r) => r.description || '' },
      { label: 'Category',        display: (r) => r.category || 'N/A',                                                                                      raw: (r) => r.category || '' },
      { label: 'Office',          display: (r) => r.office || 'N/A',                                                                                        raw: (r) => r.office || '' },
      { label: 'Acq. Date',       display: (r) => fmtDate(r.acquisitionDate),                                                                             raw: (r) => r.acquisitionDate || '' },
      { label: 'Expected Life',   display: (r) => r.usefulLifeYears ? `${r.usefulLifeYears} yrs` : 'N/A',                                                  raw: (r) => r.usefulLifeYears || '' },
      { label: 'End of Life',     display: (r) => fmtDate(r.endOfLife),                                                                                   raw: (r) => r.endOfLife || '' },
      { label: 'Reason',          display: (r) => r.reason || 'N/A',                                                                                        raw: (r) => r.reason || '' },
      { label: 'Condition',       display: (r) => r.condition || 'N/A',                                                                                     raw: (r) => r.condition || '' },
      { label: 'Acq. Value',      display: (r) => fmtMoney(r.unitValue),                                                                                  raw: (r) => r.unitValue != null ? Number(r.unitValue).toFixed(2) : '' },
      { label: 'Est. Cost',       display: (r) => <span className="font-semibold text-amber-700 dark:text-amber-300">{fmtMoney(r.estimatedCost)}</span>, raw: (r) => Number(r.estimatedCost).toFixed(2) },
    ],
  },
  {
    id: 'depreciation',
    title: 'Depreciation Schedule',
    printTitle: 'SCHEDULE OF DEPRECIATION OF PROPERTY, PLANT AND EQUIPMENT',
    certification: [
      { label: 'Prepared by:', caption: 'Signature over Printed Name of Property Custodian / GSO Staff' },
      { label: 'Certified Correct by:', caption: 'Signature over Printed Name of Municipal Accountant' },
    ],
    description: 'Straight-line depreciation of assets in use as of today: residual value, monthly depreciation, accumulated depreciation and book value.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M12 13a1 1 0 100 2h5a1 1 0 001-1V9a1 1 0 10-2 0v2.586l-4.293-4.293a1 1 0 00-1.414 0L8 9.586 3.707 5.293a1 1 0 00-1.414 1.414l5 5a1 1 0 001.414 0L11 9.414 14.586 13H12z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getDepreciation({ items: true })).data.items
    },
    dateField: 'acquisitionDate',
    extraRows: (rows) => {
      const sum = (k) => rows.reduce((s, r) => s + (Number(r[k]) || 0), 0)
      return [
        ...rows,
        {
          propertyNumber: 'TOTAL', description: `${rows.length} assets`, category: '', acquisitionDate: '',
          totalCost: sum('totalCost'), residualValue: sum('residualValue'), depreciableCost: sum('depreciableCost'),
          usefulLifeMonths: '', remainingLifeMonths: '', monthlyDepreciation: sum('monthlyDepreciation'),
          depreciationExpense: sum('depreciationExpense'), accumulatedDepreciation: sum('accumulatedDepreciation'), bookValue: sum('bookValue'),
        },
      ]
    },
    headers: [
      { label: 'Property No.',        display: (r) => <span className="font-mono text-xs">{r.propertyNumber || 'N/A'}</span>,                      raw: (r) => r.propertyNumber || '' },
      { label: 'Description',         display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.description || 'N/A'}</span>, raw: (r) => r.description || '' },
      { label: 'Category',            display: (r) => r.category || 'N/A',                                                                         raw: (r) => r.category || '' },
      { label: 'Acquisition Date',    display: (r) => fmtDate(r.acquisitionDate),                                                                raw: (r) => r.acquisitionDate || '' },
      { label: 'Total Cost',          display: (r) => fmtMoney(r.totalCost),                                                                     raw: (r) => Number(r.totalCost).toFixed(2) },
      { label: 'Residual Value',      display: (r) => fmtMoney(r.residualValue),                                                                 raw: (r) => Number(r.residualValue).toFixed(2) },
      { label: 'Depreciable Cost',    display: (r) => fmtMoney(r.depreciableCost),                                                               raw: (r) => Number(r.depreciableCost).toFixed(2) },
      { label: 'Useful Life (months)', display: (r) => r.usefulLifeMonths,                                                                       raw: (r) => r.usefulLifeMonths },
      { label: 'Remaining Useful Life', display: (r) => r.remainingLifeMonths,                                                                   raw: (r) => r.remainingLifeMonths },
      { label: 'Monthly Depreciation', display: (r) => r.monthlyDepreciation != null ? fmtMoney(r.monthlyDepreciation) : '-',                   raw: (r) => r.monthlyDepreciation != null ? Number(r.monthlyDepreciation).toFixed(2) : '-' },
      { label: 'Depreciation Expense', display: (r) => Number(r.depreciationExpense) ? fmtMoney(r.depreciationExpense) : '-',                    raw: (r) => Number(r.depreciationExpense) ? Number(r.depreciationExpense).toFixed(2) : '-' },
      { label: 'Accumulated Depreciation', display: (r) => fmtMoney(r.accumulatedDepreciation),                                                  raw: (r) => Number(r.accumulatedDepreciation).toFixed(2) },
      { label: 'Book Value',          display: (r) => <span className="font-semibold text-slate-900 dark:text-white">{fmtMoney(r.bookValue)}</span>, raw: (r) => Number(r.bookValue).toFixed(2) },
    ],
  },
  {
    // One row per category: the last 3 full years, this year so far, and next year's estimate
    // (MaintenanceForecastService), with a total row.
    id: 'maintenanceforecast',
    title: 'Repairs & Maintenance Forecast',
    printTitle: 'REPAIRS AND MAINTENANCE COST AND FORECAST',
    certification: [
      { label: 'Prepared by:', caption: 'Signature over Printed Name of Property Custodian / GSO Staff' },
      { label: 'Approved by:', caption: 'Signature over Printed Name of Municipal General Services Officer' },
    ],
    description: `What repairs and maintenance cost in each of the last 3 years, by type of property, and about how much to budget for ${FORECAST_YEAR}.`,
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getMaintenanceForecast({ priceIncrease: 3 })).data.byCategory
    },
    extraRows: (rows) => {
      if (!rows.length) return rows
      const sum = (get) => rows.reduce((s, r) => s + (Number(get(r)) || 0), 0)
      const perYear = Object.fromEntries(FORECAST_HISTORY.map((y) => [y, sum((r) => r.perYear?.[y])]))
      return [...rows, { category: 'TOTAL', perYear, average: sum((r) => r.average), forecast: sum((r) => r.forecast), trend: '' }]
    },
    headers: [
      { label: 'Type of Property', display: (r) => <span className={r.category === 'TOTAL' ? 'font-bold' : 'font-medium text-slate-900 dark:text-white'}>{r.category}</span>, raw: (r) => r.category },
      ...FORECAST_HISTORY.map((y) => ({
        label: String(y) === String(FORECAST_YEAR - 1) ? `${y} (so far)` : String(y),
        display: (r) => fmtMoney(r.perYear?.[y] ?? 0),
        raw: (r) => Number(r.perYear?.[y] ?? 0).toFixed(2),
      })),
      { label: '3-Year Average', display: (r) => fmtMoney(r.average),                                                              raw: (r) => Number(r.average).toFixed(2) },
      { label: 'Trend',          display: (r) => TREND_LABEL[r.trend] || '',                                                        raw: (r) => TREND_LABEL[r.trend] || '' },
      { label: `Estimate ${FORECAST_YEAR}`, display: (r) => <span className="font-semibold text-amber-700 dark:text-amber-300">{fmtMoney(r.forecast)}</span>, raw: (r) => Number(r.forecast).toFixed(2) },
    ],
  },
  {
    // Was the Maintenance Ledger; now the GSO's Repair and Maintenance Card, one per asset (the
    // same ?report=maintenance link).
    id: 'maintenance',
    title: 'Repair and Maintenance Card',
    description: 'A card for each asset that has been repaired: every repair in date order, with its parts, labor and cost of repair.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      // the maintenance records carry the asset's number and name; the acquisition cost and
      // department come from the asset list
      const [maintenance, assets] = await Promise.all([getAllMaintenance(), getAllAssets()])
      return maintenanceCardsOf(maintenance.data, assets.data)
    },
    selectable: {
      toItems: (cards) => cards,
      noun: ['maintenance card', 'maintenance cards'],
      placeholder: 'Search property No., asset, department, repair',
      hint: 'Tick one or more assets to export their repair and maintenance cards.',
      none: 'No approved maintenance records yet, so there are no cards.',
      search: (c, q) => [c.asset.propertyNumber, c.asset.description, c.asset.office?.officeName,
        ...c.records.map((r) => r.actionsTaken), ...c.records.flatMap((r) => (r.items || []).map((i) => i.particular))]
        .some((v) => String(v || '').toLowerCase().includes(q)),
      label: (c) => `maintenance card ${c.asset.propertyNumber}`,
      columns: [
        { label: 'Property No.',    cell: (c) => <span className="font-mono text-xs text-slate-900 dark:text-white whitespace-nowrap">{c.asset.propertyNumber}</span> },
        { label: 'Machine / Equipment', cell: (c) => c.asset.description || 'N/A' },
        { label: 'Department',      cell: (c) => c.asset.office?.officeName || 'N/A' },
        { label: 'Repairs',         cell: (c) => c.repairs, right: true },
        { label: 'Cost of Repairs', cell: (c) => fmtMoney(c.totalCost), right: true },
        { label: 'Last Repair',     cell: (c) => <span className="whitespace-nowrap">{fmtDate(c.lastRepair)}</span> },
      ],
      expandLabel: 'card lines',
      expanded: (c) => <MiniTable headers={MAINTENANCE_CARD_HEADERS} rows={cardLines(c.records)} rowKey={(l, i) => i} />,
      summary: (items) => `${items.reduce((n, c) => n + c.repairs, 0)} repairs · Cost of repairs ${fmtMoney(items.reduce((n, c) => n + c.totalCost, 0))}`,
      exportExcel: (items) => exportMaintenanceCardsExcel(items),
      exportPdf: (items) => printMaintenanceCards(items),
    },
    headers: [],
  },
  {
    id: 'par',
    title: 'PAR (Property Acknowledgment Receipt)',
    description: 'Select one or more PAR numbers to print their receipts, with the accountable person and total amount.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path d="M9 2a1 1 0 000 2h2a1 1 0 100-2H9z" />
        <path fillRule="evenodd" d="M4 5a2 2 0 012-2 3 3 0 003 3h2a3 3 0 003-3 2 2 0 012 2v11a2 2 0 01-2 2H6a2 2 0 01-2-2V5zm9.707 5.707a1 1 0 00-1.414-1.414L9 12.586l-1.293-1.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getAllAssets()).data
    },
    // No date filter: the table lists PAR numbers, and the ticked ones are exported.
    selectable: {
      toItems: parGroupsOf,
      noun: ['PAR number', 'PAR numbers'],
      placeholder: 'Search PAR, office, person, property No.',
      hint: 'Tick one or more PAR numbers to export their receipts.',
      none: 'No assets have a PAR number yet.',
      search: (g, q) => g.par.toLowerCase().includes(q) || g.office.toLowerCase().includes(q)
        || g.receivedBy.toLowerCase().includes(q)
        || g.rows.some((r) => String(r.propertyNumber || '').toLowerCase().includes(q)),
      label: (g) => `PAR No. ${g.par}`,
      columns: [
        { label: 'PAR No.',            cell: (g) => <span className="font-mono text-xs text-slate-900 dark:text-white whitespace-nowrap">{g.par}</span> },
        { label: 'Office',             cell: (g) => g.office || 'N/A' },
        { label: 'Accountable Person', cell: (g) => g.receivedBy || 'N/A' },
        { label: 'Items',              cell: (g) => g.rows.length, right: true },
        { label: 'Total Amount',       cell: (g) => fmtMoney(g.total), right: true },
      ],
      expandLabel: 'items',
      expanded: (g) => <MiniTable headers={PAR_HEADERS} rows={g.rows} rowKey={(a) => a.id} />,
      summary: (items) => `${items.reduce((n, g) => n + g.rows.length, 0)} items · Total ${fmtMoney(items.reduce((n, g) => n + g.total, 0))}`,
      exportExcel: (items) => exportParExcel(items),
      exportPdf: (items) => exportParPDF(items),
    },
    headers: PAR_HEADERS,
  },
  {
    id: 'propertycard',
    title: 'Property Card',
    description: 'A card for each transferred asset: who it was transferred to and which office, in date order.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path d="M8 5a1 1 0 100 2h5.586l-1.293 1.293a1 1 0 001.414 1.414l3-3a1 1 0 000-1.414l-3-3a1 1 0 10-1.414 1.414L13.586 5H8zM12 15a1 1 0 100-2H6.414l1.293-1.293a1 1 0 10-1.414-1.414l-3 3a1 1 0 000 1.414l3 3a1 1 0 001.414-1.414L6.414 15H12z" />
      </svg>
    ),
    async load() {
      return (await getPropertyCards()).data
    },
    // Only assets that have been transferred have a card; the backend leaves the rest out.
    selectable: {
      toItems: (cards) => cards.map((c) => ({ ...c, key: String(c.assetId) })),
      noun: ['property card', 'property cards'],
      placeholder: 'Search property No., office, person',
      hint: 'Tick one or more assets to export their property cards.',
      none: 'No asset has been transferred yet, so there are no property cards.',
      search: (c, q) => [c.propertyNumber, c.parNumber, c.description, c.currentOffice, c.currentAccountable,
        ...c.entries.map((e) => e.transferTo), ...c.entries.map((e) => e.office)]
        .some((v) => String(v || '').toLowerCase().includes(q)),
      label: (c) => `property card ${c.propertyNumber}`,
      columns: [
        { label: 'Property No.',       cell: (c) => <span className="font-mono text-xs text-slate-900 dark:text-white whitespace-nowrap">{c.propertyNumber}</span> },
        { label: 'Description',        cell: (c) => c.description || 'N/A' },
        { label: 'Current Office',     cell: (c) => c.currentOffice || 'N/A' },
        { label: 'Accountable Person', cell: (c) => c.currentAccountable || 'N/A' },
        { label: 'Transfers',          cell: (c) => c.transferCount, right: true },
        { label: 'Last Transfer',      cell: (c) => <span className="whitespace-nowrap">{fmtDate(c.lastTransferDate)}</span> },
      ],
      expandLabel: 'card lines',
      expanded: (c) => <MiniTable headers={CARD_ENTRY_HEADERS} rows={c.entries} rowKey={(e, i) => i} />,
      summary: (items) => `${items.reduce((n, c) => n + c.transferCount, 0)} transfers`,
      exportExcel: (items) => exportPropertyCardsExcel(items),
      exportPdf: (items) => printPropertyCards(items),
    },
    headers: [],
  },
  {
    id: 'iirup',
    title: 'IIRUP (Unserviceable Property)',
    printTitle: 'INVENTORY AND INSPECTION REPORT OF UNSERVICEABLE PROPERTY',
    description: 'COA-format Inventory and Inspection Report of Unserviceable Property, for items pending disposal.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getAllDisposal()).data
    },
    dateField: 'inspectionDate',
    headers: [
      { label: 'Date Acquired', printWidth: 6.5,                 display: (r) => fmtDate(r.asset?.acquisitionDate),                                                                raw: (r) => r.asset?.acquisitionDate || '' },
      { label: 'Particulars/Article', printWidth: 12,           display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.asset?.description || 'N/A'}</span>, raw: (r) => r.asset?.description || '' },
      { label: 'Property No.', printWidth: 9.5,                  display: (r) => <span className="font-mono text-xs">{r.asset?.propertyNumber || 'N/A'}</span>,                     raw: (r) => r.asset?.propertyNumber || '' },
      { label: 'PAR No.', printWidth: 8,                     display: (r) => <span className="font-mono text-xs">{r.asset?.parNumber || 'N/A'}</span>,                     raw: (r) => r.asset?.parNumber || '' },
      { label: 'Qty.', printWidth: 4,                          display: (r) => r.asset?.quantity ?? 1,                                                                           raw: (r) => r.asset?.quantity ?? 1 },
      { label: 'Unit Cost', printWidth: 7,                     display: (r) => fmtMoney(r.asset?.unitValue),                                                                     raw: (r) => r.asset?.unitValue != null ? Number(r.asset.unitValue).toFixed(2) : '' },
      { label: 'Total Cost', printWidth: 7,                    display: (r) => fmtMoney((Number(r.asset?.unitValue) || 0) * (Number(r.asset?.quantity) || 1)),                   raw: (r) => ((Number(r.asset?.unitValue) || 0) * (Number(r.asset?.quantity) || 1)).toFixed(2) },
      { label: 'Remarks', printWidth: 10,                       display: (r) => r.inspectionFindings ? <span className="max-w-[11.25rem] truncate block" title={r.inspectionFindings}>{r.inspectionFindings}</span> : 'N/A', raw: (r) => r.inspectionFindings || '' },
      { label: 'Sale', printWidth: 4,                          display: (r) => r.recommendedMethod === 'SALE'        ? (r.asset?.quantity ?? 1) : 'N/A',                           raw: (r) => r.recommendedMethod === 'SALE'        ? (r.asset?.quantity ?? 1) : '' },
      { label: 'Transfer', printWidth: 6.5,                      display: (r) => r.recommendedMethod === 'TRANSFER'    ? (r.asset?.quantity ?? 1) : 'N/A',                           raw: (r) => r.recommendedMethod === 'TRANSFER'    ? (r.asset?.quantity ?? 1) : '' },
      { label: 'Destruction', printWidth: 8.5,                   display: (r) => r.recommendedMethod === 'DESTRUCTION' ? (r.asset?.quantity ?? 1) : 'N/A',                           raw: (r) => r.recommendedMethod === 'DESTRUCTION' ? (r.asset?.quantity ?? 1) : '' },
      { label: 'Others (Specify)', printWidth: 6,              display: (r) => r.recommendedMethod === 'OTHERS'      ? (r.asset?.quantity ?? 1) : 'N/A',                           raw: (r) => r.recommendedMethod === 'OTHERS'      ? (r.asset?.quantity ?? 1) : '' },
      { label: 'Total', printWidth: 5,                         display: (r) => r.asset?.quantity ?? 1,                                                                           raw: (r) => r.asset?.quantity ?? 1 },
      { label: 'Appraised Value', printWidth: 6.5,               display: (r) => fmtMoney(r.appraisedValue),                                                                       raw: (r) => r.appraisedValue != null ? Number(r.appraisedValue).toFixed(2) : '' },
      { label: 'OR No.', printWidth: 5,                        display: (r) => r.orNumber || 'N/A',                                                                                raw: (r) => r.orNumber || '' },
      { label: 'Amount', printWidth: 6.5,                        display: (r) => fmtMoney(r.amount),                                                                               raw: (r) => r.amount != null ? Number(r.amount).toFixed(2) : '' },
    ],
    certification: [
      { label: 'Inspected by:',          caption: 'Signature over Printed Name of GSO Inspector' },
      { label: 'Certified Correct by:',  caption: 'Signature over Printed Name of Inventory Committee Chairman' },
      { label: 'Recommending Approval:', caption: 'Signature over Printed Name of Head of Office' },
      { label: 'Approved by:',           caption: 'Signature over Printed Name of Local Chief Executive (Municipal Mayor)' },
    ],
  },
]

// ── Export helpers ────────────────────────────────────────────────────────────
// File and sheet names can't contain : \ / ? * [ ] - PAR numbers like 2026-09:GA21231 do.
const safeName = (s) => s.replace(/[:\\/?*[\]]/g, '-')
// xlsx is ~400 KB; load it only when someone exports
const loadXlsx = () => import('xlsx')

async function exportExcel(rows, headers, title) {
  const XLSX = await loadXlsx()
  const data = rows.map((row) => {
    const obj = {}
    headers.forEach(({ label, raw }) => { obj[label] = raw(row) })
    return obj
  })
  const ws = XLSX.utils.json_to_sheet(data)
  const colWidths = headers.map(({ label, raw }) => ({
    wch: Math.max(label.length, ...rows.map((r) => String(raw(r)).length)) + 2,
  }))
  ws['!cols'] = colWidths
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, safeName(title).slice(0, 31))
  XLSX.writeFile(wb, `${safeName(title).replace(/\s+/g, '_')}_${new Date().toISOString().slice(0, 10)}.xlsx`)
}

// Printed in the standard (RPCPPE) format: the title block and table header on every page,
// at most 8 rows a page, and the report's signatures once after the last page.
const ISO_DATE = /^\d{4}-\d{2}-\d{2}(T[\d:.]+)?$/
function printCell(v) {
  const s = String(v ?? '')
  if (ISO_DATE.test(s)) return `<td class="c">${esc(fmtDate(s))}</td>`
  if (/^-?\d+\.\d{2}$/.test(s)) return `<td class="r">${Number(s).toLocaleString('en-PH', { minimumFractionDigits: 2 })}</td>`
  if (/^\d+$/.test(s)) return `<td class="c">${s}</td>`
  return `<td>${esc(s)}</td>`
}

function exportPDF(rows, report, { from, to }, settings) {
  const s = { ...RPCPPE_DEFAULTS, ...settings }
  const today = manilaDateKey(new Date())
  const period = from
    ? `For the period ${longDate(from)} to ${longDate(to || today)}`
    : `As at ${longDate(to || today)}`
  // a heading may break after a slash ("PARTICULARS/ ARTICLE") rather than mid-word
  const headerCells = report.headers.map((h) => `<th>${esc(h.label.toUpperCase()).replace(/\//g, '/<wbr>')}</th>`).join('')
  // column widths in proportion to `printWidth` where a report gives them; otherwise equal
  const widthTotal = report.headers.reduce((t, h) => t + (h.printWidth || 0), 0)
  const cols = widthTotal ? `<colgroup>${report.headers.map((h) => `<col style="width:${((h.printWidth || 0) / widthTotal * 100).toFixed(2)}%">`).join('')}</colgroup>` : ''
  const pages = toPages(rows).map((pageRows) => `<section class="form${report.headers.length > 12 ? ' dense' : ''}">
  <div class="title">
    <h1>${esc(report.printTitle || report.title.toUpperCase())}</h1>
    <h2>${esc((s.entity || '').toUpperCase())}</h2>
    <p>${esc(period)}</p>
  </div>
  <p class="fund">Fund Cluster : ${esc((s.fundCluster || '').toUpperCase())}</p>
  <table>
    ${cols}
    <thead><tr>${headerCells}</tr></thead>
    <tbody>${pageRows.map((row) => `<tr>${report.headers.map(({ raw }) => printCell(raw(row))).join('')}</tr>`).join('')}</tbody>
  </table>
</section>`).join('\n')
  printForm(report.printTitle || report.title, pages, report.certification)
}

// ── PAR form export ───────────────────────────────────────────────────────────
// Follows the LGU's printed Property Acknowledgment Receipt: one block per item, where
// the Description cell runs down several rows - item name, Brand/Model, S/N, then
// "Technical Specifications:" and one spec per row (from the asset's free-text specs).
const PAR_ENTITY = 'San Jose, Batangas'
const PAR_FUND   = 'General Fund'

function parDescriptionLines(a) {
  const specs = String(a.specifications || '').split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
  const ident = specs.filter((l) => /^(brand|model)\s*:/i.test(l))
  const rest  = specs.filter((l) => !/^(brand|model)\s*:/i.test(l))
  const lines = [a.description || 'N/A', ...ident]
  if (a.serialNumber) lines.push(`S/N: ${a.serialNumber}`)
  if (rest.length) lines.push('', 'Technical Specifications:', ...rest)
  return lines
}

function parHeader(rows, par) {
  return {
    office: uniqueJoined(rows, (r) => r.office?.officeName) || 'No office assigned',
    receivedBy: uniqueJoined(rows, (r) => r.accountablePerson?.fullName),
    total: rows.reduce((s, r) => s + lineAmount(r), 0),
    par,
  }
}

// One printed form per PAR; several selected PARs print as one document, a page each.
function parFormHtml(rows, par) {
  const h = parHeader(rows, par)
  const body = rows.map((a) => parDescriptionLines(a).map((line, i) => {
    const cls = line === 'Technical Specifications:' ? ' class="spec-head"' : ''
    return i === 0
      ? `<tr><td class="c">${esc(a.quantity ?? 1)}</td><td class="c">Unit</td><td${cls}>${esc(line)}</td><td class="c">${esc(a.propertyNumber)}</td><td class="c">${esc(fmtDate(a.acquisitionDate))}</td><td class="r">${esc(fmtMoney(lineAmount(a)))}</td></tr>`
      : `<tr class="cont"><td></td><td></td><td${cls}>${esc(line) || '&nbsp;'}</td><td></td><td></td><td></td></tr>`
  }).join('')).join('')

  return `<section class="par">
  <div class="title">
    <h1>PROPERTY ACKNOWLEDGMENT RECEIPT</h1>
    <h2>(${esc(h.office.toUpperCase())})</h2>
  </div>
  <div class="info">
    <div>
      <p><span>Entity Name</span>: ${esc(PAR_ENTITY)}</p>
      <p><span>Fund Cluster</span>: ${esc(PAR_FUND)}</p>
    </div>
    <p>PAR No. : ${esc(par)}</p>
  </div>
  <table>
    <thead><tr><th style="width:8%">Quantity</th><th style="width:8%">Unit</th><th>Description</th><th style="width:17%">Property Number</th><th style="width:11%">Date Acquired</th><th style="width:12%">Amount</th></tr></thead>
    <tbody>${body}</tbody>
    <tr class="total"><td colspan="5" style="text-align:right">TOTAL</td><td class="r">${esc(fmtMoney(h.total))}</td></tr>
  </table>
  <div class="sign">
    <div>
      <p class="who">Received by:</p>
      <p class="name">${esc(h.receivedBy)}</p>
      <p class="cap">Signature over Printed Name of End User</p>
      <p class="line"></p><p class="cap">Position/Office</p>
      <p class="line"></p><p class="cap">Date</p>
    </div>
    <div>
      <p class="who">Issued by:</p>
      <p class="name"></p>
      <p class="cap">Signature over Printed Name of Supply and/or Property Custodian</p>
      <p class="line"></p><p class="cap">Position/Office</p>
      <p class="line"></p><p class="cap">Date</p>
    </div>
  </div>
</section>`
}

function exportParPDF(groups) {
  const title = groups.length === 1 ? `PAR No. ${groups[0].par}` : `PAR Forms (${groups.length})`
  const html = `<!DOCTYPE html>
<html>
<head>
  <title>${esc(title)}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    :root { color-scheme: light; }
    body { font-family: Calibri, 'Segoe UI', Arial, sans-serif; font-size: 12px; padding: 28px; color: #000; background: #fff; }
    .title { text-align: center; font-family: 'Times New Roman', serif; }
    .title h1 { font-size: 20px; font-weight: 700; letter-spacing: .02em; }
    .title h2 { font-size: 16px; font-weight: 700; margin-top: 2px; }
    .info { display: flex; justify-content: space-between; align-items: flex-end; margin: 18px 0 8px; font-family: 'Times New Roman', serif; font-weight: 700; font-size: 14px; }
    .info p { line-height: 1.5; }
    .info span { display: inline-block; width: 110px; }
    table { width: 100%; border-collapse: collapse; }
    th { font-family: 'Times New Roman', serif; font-size: 14px; font-weight: 700; padding: 8px 6px; border: 1px solid #000; text-align: center; }
    td { padding: 3px 8px; border-left: 1px solid #000; border-right: 1px solid #000; border-top: 1px solid #000; vertical-align: top; }
    tr.cont td { border-top: 1px solid #bbb; }
    tbody tr:last-child td { border-bottom: 1px solid #000; }
    td.c { text-align: center; } td.r { text-align: right; white-space: nowrap; }
    td.spec-head { font-style: italic; }
    tr.total td { border: 1px solid #000; font-weight: 700; padding: 6px 8px; }
    .sign { display: flex; border: 1px solid #000; border-top: none; page-break-inside: avoid; }
    .sign > div { flex: 1; padding: 10px 14px 14px; }
    .sign > div + div { border-left: 1px solid #000; }
    .sign .who { font-weight: 700; }
    .sign .name { margin-top: 30px; border-bottom: 1px solid #000; text-align: center; font-weight: 700; min-height: 18px; text-transform: uppercase; }
    .sign .cap { text-align: center; font-size: 10px; margin-bottom: 12px; }
    .sign .line { margin-top: 18px; border-bottom: 1px solid #000; }
    .par + .par { page-break-before: always; margin-top: 28px; }
    @media print { body { padding: 0; } .par + .par { margin-top: 0; } }
  </style>
</head>
<body>
  ${groups.map((g) => parFormHtml(g.rows, g.par)).join('\n')}
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
</body>
</html>`

  openPrintWindow().write(html)
}

// One sheet per PAR in a single workbook.
async function exportParExcel(groups) {
  const XLSX = await loadXlsx()
  const wb = XLSX.utils.book_new()
  const used = new Set()
  groups.forEach(({ rows, par }) => {
    let name = safeName(`PAR ${par}`).slice(0, 31)
    for (let n = 2; used.has(name.toUpperCase()); n++) name = `${safeName(`PAR ${par}`).slice(0, 27)} (${n})`
    used.add(name.toUpperCase())
    XLSX.utils.book_append_sheet(wb, parSheet(XLSX, rows, par), name)
  })
  const file = groups.length === 1 ? `PAR_${safeName(groups[0].par)}` : `PAR_Forms_${groups.length}`
  XLSX.writeFile(wb, `${file}_${new Date().toISOString().slice(0, 10)}.xlsx`)
}

function parSheet(XLSX, rows, par) {
  const h = parHeader(rows, par)
  const aoa = [
    ['', '', 'PROPERTY ACKNOWLEDGMENT RECEIPT'],
    ['', '', `(${h.office.toUpperCase()})`],
    [],
    ['Entity Name', '', `: ${PAR_ENTITY}`, '', 'PAR No.', `: ${par}`],
    ['Fund Cluster', '', `: ${PAR_FUND}`],
    [],
    ['Quantity', 'Unit', 'Description', 'Property Number', 'Date Acquired', 'Amount'],
  ]
  rows.forEach((a) => {
    parDescriptionLines(a).forEach((line, i) => {
      aoa.push(i === 0
        ? [a.quantity ?? 1, 'Unit', line, a.propertyNumber || '', a.acquisitionDate || '', Number(lineAmount(a).toFixed(2))]
        : ['', '', line, '', '', ''])
    })
  })
  aoa.push(['', '', '', '', 'TOTAL', Number(h.total.toFixed(2))])
  aoa.push([], ['Received by:', '', '', 'Issued by:'], [], ['', '', h.receivedBy, '', '', ''],
    ['', '', 'Signature over Printed Name of End User', '', 'Signature over Printed Name of Supply and/or Property Custodian'],
    [], ['', '', 'Position/Office', '', 'Position/Office'], [], ['', '', 'Date', '', 'Date'])

  const ws = XLSX.utils.aoa_to_sheet(aoa)
  ws['!cols'] = [{ wch: 10 }, { wch: 8 }, { wch: 60 }, { wch: 24 }, { wch: 16 }, { wch: 16 }]
  ws['!merges'] = [{ s: { r: 0, c: 0 }, e: { r: 0, c: 5 } }, { s: { r: 1, c: 0 }, e: { r: 1, c: 5 } }]
  ws.A1 = { t: 's', v: 'PROPERTY ACKNOWLEDGMENT RECEIPT' }
  ws.A2 = { t: 's', v: `(${h.office.toUpperCase()})` }
  delete ws.C1; delete ws.C2
  return ws
}

// ── Pick-and-export table (PAR, Property Card) ────────────────────────────────
// One row per item. Tick one or several to export them; expand a row to see what's inside.
const CHECKBOX_CLASS = 'h-4 w-4 rounded border-slate-300 dark:border-zinc-600 text-brand-600 focus:ring-brand-500 cursor-pointer'

function SelectTable({ config, items, selected, onToggle, onToggleAll, expanded, onExpand }) {
  const allChecked  = items.length > 0 && items.every((it) => selected.has(it.key))
  const someChecked = !allChecked && items.some((it) => selected.has(it.key))
  const headCls = 'px-4 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap'

  return (
    <div data-lazy-scroll className="table-scroll rounded-lg border border-slate-200 dark:border-zinc-800">
      <table className="min-w-full text-sm divide-y divide-slate-200 dark:divide-zinc-800">
        <thead className="sticky top-0 z-10 bg-slate-50 dark:bg-zinc-900 shadow-[0_1px_0_0] shadow-slate-200 dark:shadow-zinc-800">
          <tr>
            <th className="pl-4 pr-2 py-3 w-8">
              <input type="checkbox" aria-label={`Select all ${config.noun[1]} shown`} className={CHECKBOX_CLASS}
                checked={allChecked} ref={(el) => { if (el) el.indeterminate = someChecked }}
                onChange={() => onToggleAll(items, !allChecked)} />
            </th>
            {config.columns.map((c) => <th key={c.label} className={`${headCls}${c.right ? ' text-right' : ''}`}>{c.label}</th>)}
            <th className="px-2 py-3 w-10"><span className="sr-only">Show {config.expandLabel}</span></th>
          </tr>
        </thead>
        <tbody className="bg-white dark:bg-zinc-950 divide-y divide-slate-100 dark:divide-zinc-800/60">
          {items.map((it) => {
            const isOpen = expanded === it.key
            const isChecked = selected.has(it.key)
            return [
              <tr key={it.key} onClick={() => onToggle(it.key)}
                className={`cursor-pointer transition-colors duration-100 ${isChecked ? 'bg-brand-500/5 dark:bg-brand-500/10' : 'hover:bg-slate-50 dark:hover:bg-zinc-800/50'}`}>
                <td className="pl-4 pr-2 py-3" onClick={(e) => e.stopPropagation()}>
                  <input type="checkbox" aria-label={`Select ${config.label(it)}`} className={CHECKBOX_CLASS}
                    checked={isChecked} onChange={() => onToggle(it.key)} />
                </td>
                {config.columns.map((c) => (
                  <td key={c.label} className={`px-4 py-3 text-slate-600 dark:text-zinc-300${c.right ? ' text-right tabular-nums whitespace-nowrap' : ''}`}>{c.cell(it)}</td>
                ))}
                <td className="px-2 py-3 text-right">
                  <button type="button" onClick={(e) => { e.stopPropagation(); onExpand(isOpen ? null : it.key) }}
                    aria-expanded={isOpen} aria-label={`${isOpen ? 'Hide' : 'Show'} ${config.expandLabel} of ${config.label(it)}`}
                    className="p-1 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors">
                    <svg xmlns="http://www.w3.org/2000/svg" className={`h-4 w-4 transition-transform duration-150 ${isOpen ? 'rotate-90' : ''}`} viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
                    </svg>
                  </button>
                </td>
              </tr>,
              isOpen && (
                <tr key={`${it.key}:more`} className="bg-slate-50/70 dark:bg-zinc-900/60">
                  <td />
                  <td colSpan={config.columns.length + 1} className="px-4 py-3">{config.expanded(it)}</td>
                </tr>
              ),
            ]
          })}
        </tbody>
      </table>
    </div>
  )
}

function MiniTable({ headers, rows, rowKey }) {
  return (
    <table className="min-w-full text-xs">
      <thead>
        <tr className="text-left text-slate-400 dark:text-zinc-500">
          {headers.map((h) => <th key={h.label} className="py-1.5 pr-4 font-medium whitespace-nowrap">{h.label}</th>)}
        </tr>
      </thead>
      <tbody className="divide-y divide-slate-200/70 dark:divide-zinc-800">
        {rows.map((r, i) => (
          <tr key={rowKey(r, i)}>
            {headers.map((h) => <td key={h.label} className="py-1.5 pr-4 text-slate-600 dark:text-zinc-300 whitespace-nowrap">{h.display(r)}</td>)}
          </tr>
        ))}
      </tbody>
    </table>
  )
}

// ── Date range filter ─────────────────────────────────────────────────────────

const DATE_INPUT_CLASS ='rounded-md border border-slate-200 dark:border-zinc-700 px-2.5 py-1.5 text-xs bg-white dark:bg-zinc-800 text-slate-700 dark:text-zinc-200 hover:border-slate-300 dark:hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

function DateRangeFilter({ from, to, onChange }) {
  const activePreset = (() => {
    for (const p of DATE_PRESETS) {
      const r = presetRange(p.key)
      if (r.from === from && r.to === to) return p.key
    }
    return null
  })()

  return (
    <div className="flex flex-wrap items-center gap-2">
      <div className="inline-flex items-center rounded-lg border border-slate-200 dark:border-zinc-700 bg-slate-50 dark:bg-zinc-800/60 p-0.5">
        {DATE_PRESETS.map((p) => (
          <button
            key={p.key}
            onClick={() => onChange(presetRange(p.key))}
            className={`px-2.5 py-1 rounded-md text-2xs font-medium transition-all duration-150 ${
              activePreset === p.key
                ? 'bg-white dark:bg-zinc-900 text-slate-900 dark:text-zinc-100 shadow-sm'
                : 'text-slate-400 dark:text-zinc-500 hover:text-slate-600 dark:hover:text-zinc-300'
            }`}
          >
            {p.label}
          </button>
        ))}
      </div>
      <div className="flex items-center gap-1.5">
        <DatePicker placeholder="From" value={from} max={to || undefined} onChange={(e) => onChange({ from: e.target.value, to })} className={DATE_INPUT_CLASS} />
        <span className="text-2xs text-slate-400 dark:text-zinc-600">to</span>
        <DatePicker placeholder="To" value={to} min={from || undefined} onChange={(e) => onChange({ from, to: e.target.value })} className={DATE_INPUT_CLASS} />
      </div>
      {(from || to) && (
        <button
          onClick={() => onChange({ from: '', to: '' })}
          className="text-2xs font-medium text-slate-400 dark:text-zinc-500 hover:text-red-400 transition-colors duration-150"
        >
          Clear
        </button>
      )}
    </div>
  )
}

// ── RPCPPE header details ─────────────────────────────────────────────────────
function RpcppeSettings({ value, onChange }) {
  const input = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3 py-2 text-sm bg-white dark:bg-zinc-800 text-slate-700 dark:text-zinc-200 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500'
  const label = 'text-xs font-medium text-slate-600 dark:text-zinc-400'
  const field = (key, text, extra = {}) => (
    <label className="flex flex-col gap-1">
      <span className={label}>{text}</span>
      {extra.date
        ? <DatePicker value={value[key]} onChange={onChange(key)} className={input} placeholder={extra.placeholder} />
        : <input className={input} value={value[key]} onChange={onChange(key)} placeholder={extra.placeholder} />}
    </label>
  )
  return (
    <div className="px-5 py-4 border-b border-slate-200 dark:border-zinc-800 bg-slate-50/60 dark:bg-zinc-800/20">
      <p className="text-sm font-medium text-slate-700 dark:text-zinc-200">Report details</p>
      <p className="text-xs text-slate-600 dark:text-zinc-400 mb-3">Printed at the top of each form. Items acquired after the "as at" date are left out.</p>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
        {field('asAt', 'As at', { date: true, placeholder: 'Today' })}
        {field('fundCluster', 'Fund cluster')}
        {field('officer', 'Accountable officer')}
        {field('designation', 'Designation')}
        {field('entity', 'Entity / LGU')}
        {field('assumedOn', 'Assumed accountability on', { date: true })}
      </div>
    </div>
  )
}

// ── Component ─────────────────────────────────────────────────────────────────
function Reports() {
  const { show } = useToast()
  const location = useLocation()

  const [activeId, setActiveId]     = useState(null)
  const [reportData, setReportData] = useState([])
  const [loading, setLoading]       = useState(false)
  const [dateFrom, setDateFrom]     = useState('')
  const [dateTo, setDateTo]         = useState('')
  // Replacement Forecast only: show one "Replace in" group ('NOW' or a year); '' = all
  const [replaceIn, setReplaceIn]   = useState('')
  const lazy = useLazyRows()
  // Pick-and-export reports (PAR, Property Card): search text, ticked item keys, expanded row
  const [pickSearch, setPickSearch]   = useState('')
  const [picked, setPicked]           = useState(() => new Set())
  const [expandedKey, setExpandedKey] = useState(null)
  const previewRef = useRef(null)
  // RPCPPE header details, remembered in this browser so they needn't be retyped each time
  const [rpcppeSettings, setRpcppeSettings] = useState(() => {
    try { return { ...RPCPPE_DEFAULTS, ...JSON.parse(localStorage.getItem('rpcppe-settings') || '{}') } } catch { return { ...RPCPPE_DEFAULTS } }
  })
  const setRpcppeSetting = (key) => (e) => {
    const next = { ...rpcppeSettings, [key]: e.target.value }
    setRpcppeSettings(next)
    try { localStorage.setItem('rpcppe-settings', JSON.stringify(next)) } catch { /* private window */ }
  }

  const activeReport = REPORTS.find((r) => r.id === activeId)

  const handleDateChange = ({ from, to }) => { setDateFrom(from); setDateTo(to); lazy.reset() }

  const resetFilters = () => {
    setDateFrom('')
    setDateTo('')
    setReplaceIn('')
    setPickSearch('')
    setPicked(new Set())
    setExpandedKey(null)
    lazy.reset()
  }

  const handleGenerate = async (report) => {
    if (activeId === report.id) {
      setActiveId(null)
      setReportData([])
      resetFilters()
      return
    }
    setLoading(true)
    setActiveId(report.id)
    setReportData([])
    resetFilters()
    try {
      const data = await report.load()
      setReportData(data)
      setTimeout(() => previewRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 100)
    } catch {
      show('Failed to load report data.', 'error')
      setActiveId(null)
    } finally {
      setLoading(false)
    }
  }

  // Dashboard's "Reports" quick action links straight into a specific COA
  // report, e.g. /reports?report=rpcppe, instead of leaving the user to find
  // it among the cards themselves. Home's Budget & Planning cards also pass
  // &replaceIn=NOW or &replaceIn=<year> to open the forecast on one group.
  useEffect(() => {
    const params = new URLSearchParams(location.search)
    const report = REPORTS.find((r) => r.id === params.get('report'))
    if (report) {
      handleGenerate(report)
      if (report.id === 'replacement' && params.get('replaceIn')) setReplaceIn(params.get('replaceIn'))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Date filter runs on the raw loaded rows first, then any per-report
  // aggregation (`transform`, e.g. the Condition Report's grouping) runs on
  // top of that - so filtering a range re-aggregates instead of just hiding rows.
  const pick = activeReport?.selectable
  const pickItems = useMemo(() => (pick ? pick.toItems(reportData, rpcppeSettings) : []), [reportData, pick, rpcppeSettings])

  const displayRows = useMemo(() => {
    if (!activeReport) return []
    if (pick) {
      const q = pickSearch.trim().toLowerCase()
      return q ? pickItems.filter((it) => pick.search(it, q)) : pickItems
    }
    let filtered = applyDateFilter(reportData, activeReport.dateField, dateFrom, dateTo)
    if (activeReport.id === 'replacement' && replaceIn) filtered = filtered.filter((r) => r.replaceIn === replaceIn)
    return activeReport.transform ? activeReport.transform(filtered) : filtered
  }, [reportData, activeReport, dateFrom, dateTo, replaceIn, pick, pickItems, pickSearch])

  // "Replace in" choices for the Replacement Forecast, in the order the backend sends them
  const replaceInOptions = useMemo(
    () => (activeReport?.id === 'replacement' ? [...new Set(reportData.map((r) => r.replaceIn).filter(Boolean))] : []),
    [activeReport, reportData],
  )

  const isDateFiltered = Boolean(dateFrom || dateTo || replaceIn)
  // Kept in list order so exported forms come out in the same order as the table.
  const pickedItems = pickItems.filter((it) => picked.has(it.key))
  const canExport = !loading && reportData.length > 0
  // Pick-and-export reports keep their export buttons visible but disabled until something is ticked.
  const exportDisabled = Boolean(pick) && pickedItems.length === 0
  const exportCount = pick && pickedItems.length > 0 ? ` (${pickedItems.length})` : ''

  const togglePicked = (key) => setPicked((prev) => {
    const next = new Set(prev)
    if (next.has(key)) next.delete(key)
    else next.add(key)
    return next
  })
  const setManyPicked = (items, checked) => setPicked((prev) => {
    const next = new Set(prev)
    items.forEach((it) => (checked ? next.add(it.key) : next.delete(it.key)))
    return next
  })

  // Every asset is its own row, same as the Assets table - no grouping by model.
  // Lazy scroll, as on the list pages; pick-and-export reports draw their items (PARs, cards) the same way.
  const pagedRows = displayRows.slice(0, lazy.shown)

  const renderReportRow = (row, key) => (
    <tr key={key} className="hover:bg-slate-50 dark:hover:bg-zinc-800/50 transition-colors duration-100">
      {activeReport.headers.map((h) => (
        <td key={h.label} className="px-4 py-3 text-slate-600 dark:text-zinc-300 whitespace-nowrap">
          {h.display(row)}
        </td>
      ))}
    </tr>
  )

  const getExportRows = () => {
    return activeReport?.extraRows ? activeReport.extraRows(displayRows) : displayRows
  }

  return (
    <MainLayout>
      {/* ── Report type cards ──────────────────────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-5 mb-6">
        {REPORTS.map((report) => {
          const isActive = activeId === report.id
          return (
            <div
              key={report.id}
              onClick={() => handleGenerate(report)}
              className={`bg-white dark:bg-zinc-900 rounded-xl border p-5 flex items-start gap-4 cursor-pointer transition-all duration-200 group ${
                isActive
                  ? 'border-brand-500/50 ring-1 ring-brand-500/30'
                  : 'border-slate-200 dark:border-zinc-800 hover:border-slate-300 dark:hover:border-zinc-700'
              }`}
            >
              <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 transition-all duration-150 ${
                isActive
                  ? 'bg-brand-500/15 text-brand-400'
                  : 'bg-slate-100 dark:bg-zinc-800 text-slate-500 dark:text-zinc-400 group-hover:bg-brand-500/10 group-hover:text-brand-400'
              }`}>
                {report.icon}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">{report.title}</p>
                <p className="text-xs text-slate-400 dark:text-zinc-500 mt-0.5 leading-relaxed">{report.description}</p>
                <button className={`mt-3 text-xs font-semibold flex items-center gap-1 transition-colors duration-150 ${isActive ? 'text-brand-400' : 'text-brand-500 hover:text-brand-400'}`}>
                  {isActive ? 'Collapse' : 'Generate Report'}
                  <svg xmlns="http://www.w3.org/2000/svg" className={`h-3.5 w-3.5 transition-transform duration-200 ${isActive ? 'rotate-90' : 'group-hover:translate-x-0.5'}`} viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
                  </svg>
                </button>
              </div>
              {isActive && <span className="flex-shrink-0 w-2 h-2 rounded-full bg-brand-400 mt-1" />}
            </div>
          )
        })}
      </div>

      {/* ── Report preview ─────────────────────────────────────────────── */}
      {activeId && (
        <div ref={previewRef} className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
          <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div>
              <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">{activeReport?.title}</p>
              {!loading && (
                <p className="text-xs text-slate-400 dark:text-zinc-500 mt-px">
                  {displayRows.length} {pick
                    ? pick.noun[displayRows.length === 1 ? 0 : 1]
                    : (displayRows.length === 1 ? 'record' : 'records')}
                  {pick && pickSearch.trim() && pickItems.length !== displayRows.length && (
                    <span className="text-slate-300 dark:text-zinc-600"> (of {pickItems.length})</span>
                  )}
                  {isDateFiltered && !activeReport?.aggregated && reportData.length !== displayRows.length && (
                    <span className="text-slate-300 dark:text-zinc-600"> (of {reportData.length})</span>
                  )}
                </p>
              )}
            </div>
            {canExport && (
              <div className="flex flex-wrap gap-2">
                <Button variant="secondary" size="md" disabled={exportDisabled} onClick={() => pick ? pick.exportExcel(pickedItems, rpcppeSettings) : exportExcel(getExportRows(), activeReport.headers, activeReport.title)}>
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 sm:mr-1.5 text-emerald-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
                  </svg>
                  <span className="hidden sm:inline">Export Excel{exportCount}</span>
                </Button>
                <Button variant="secondary" size="md" disabled={exportDisabled} onClick={() => pick ? pick.exportPdf(pickedItems, rpcppeSettings) : exportPDF(getExportRows(), activeReport, { from: dateFrom, to: dateTo }, rpcppeSettings)}>
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 sm:mr-1.5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
                  </svg>
                  <span className="hidden sm:inline">Print / PDF{exportCount}</span>
                </Button>
              </div>
            )}
          </div>

          {!loading && activeReport?.rpcppeSettings && reportData.length > 0 && (
            <RpcppeSettings value={rpcppeSettings} onChange={setRpcppeSetting} />
          )}

          {!loading && pick && pickItems.length > 0 && (
            <div className="px-5 py-3 border-b border-slate-200 dark:border-zinc-800 bg-slate-50/60 dark:bg-zinc-800/20 flex flex-wrap items-center gap-3">
              <label htmlFor="pick-search" className="sr-only">Search {pick.noun[1]}</label>
              <input
                id="pick-search"
                type="search"
                value={pickSearch}
                onChange={(e) => { setPickSearch(e.target.value); lazy.reset() }}
                placeholder={pick.placeholder}
                className="w-80 max-w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3 py-2 text-sm bg-white dark:bg-zinc-800 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
              />
              <p className="text-sm text-slate-500 dark:text-zinc-400" aria-live="polite">
                {pickedItems.length > 0 ? (
                  <>
                    <span className="font-medium text-slate-700 dark:text-zinc-200">{pickedItems.length} selected</span>
                    {' · '}{pick.summary(pickedItems)}
                    <button type="button" onClick={() => setPicked(new Set())}
                      className="ml-3 text-xs font-medium text-slate-400 dark:text-zinc-500 hover:text-red-400 transition-colors">
                      Clear selection
                    </button>
                  </>
                ) : pick.hint}
              </p>
            </div>
          )}

          {!loading && reportData.length > 0 && activeReport?.dateField && (
            <div className="px-5 py-3 border-b border-slate-200 dark:border-zinc-800 bg-slate-50/60 dark:bg-zinc-800/20 space-y-3">
              {replaceInOptions.length > 0 && (
                <div role="group" aria-label="Replace in" className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium text-slate-700 dark:text-zinc-300 mr-1">Replace in:</span>
                  {['', ...replaceInOptions].map((key) => {
                    const on = replaceIn === key
                    return (
                      <button key={key || 'all'} type="button" aria-pressed={on}
                        onClick={() => { setReplaceIn(key); lazy.reset() }}
                        className={`px-3 py-1.5 rounded-md border text-sm font-medium transition-colors ${on
                          ? 'bg-brand-700 border-brand-700 text-white'
                          : 'bg-white dark:bg-zinc-900 border-slate-300 dark:border-zinc-700 text-slate-700 dark:text-zinc-200 hover:border-brand-600 hover:text-brand-800 dark:hover:text-brand-200'}`}>
                        {key === '' ? 'All' : key === 'NOW' ? 'Now' : key}
                      </button>
                    )
                  })}
                </div>
              )}
              <DateRangeFilter from={dateFrom} to={dateTo} onChange={handleDateChange} />
            </div>
          )}

          <div data-lazy-scope className="p-4">
            {loading ? (
              <div className="overflow-x-auto rounded-lg border border-slate-200 dark:border-zinc-800">
                <table className="min-w-full text-sm">
                  <thead className="bg-slate-50 dark:bg-zinc-900">
                    <tr>{Array.from({ length: 5 }).map((_, i) => (<th key={i} className="px-4 py-3"><div className="animate-pulse h-2.5 w-16 rounded bg-slate-200 dark:bg-zinc-700" /></th>))}</tr>
                  </thead>
                  <tbody className="bg-white dark:bg-zinc-950 divide-y divide-slate-100 dark:divide-zinc-800/60">
                    {Array.from({ length: 6 }).map((_, i) => (
                      <tr key={i}>{Array.from({ length: 5 }).map((_, j) => (<td key={j} className="px-4 py-3"><div className="animate-pulse h-3 rounded bg-slate-200 dark:bg-zinc-800" style={{ width: `${60 + (j * 10) % 40}%` }} /></td>))}</tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : displayRows.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-14 gap-2 text-zinc-600">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-9 w-9" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                <p className="text-sm">
                  {pick
                    ? (pickItems.length ? `No ${pick.noun[1]} match "${pickSearch.trim()}".` : pick.none)
                    : reportData.length > 0 && isDateFiltered
                      ? 'No records in the selected date range.'
                      : 'No data available for this report.'}
                </p>
              </div>
            ) : pick ? (
              <SelectTable config={pick} items={pagedRows} selected={picked} onToggle={togglePicked}
                onToggleAll={setManyPicked} expanded={expandedKey} onExpand={setExpandedKey} />
            ) : (
              <div data-lazy-scroll className="table-scroll rounded-lg border border-slate-200 dark:border-zinc-800">
                <table className="min-w-full text-sm divide-y divide-slate-200 dark:divide-zinc-800">
                  <thead className="bg-slate-50 dark:bg-zinc-900 sticky top-0 z-10 shadow-[0_1px_0_0] shadow-slate-200 dark:shadow-zinc-800">
                    <tr>
                      {activeReport.headers.map((h) => (
                        <th key={h.label} className="px-4 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">
                          {h.label}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="bg-white dark:bg-zinc-950 divide-y divide-slate-100 dark:divide-zinc-800/60">
                    {pagedRows.map((row, i) => renderReportRow(row, `r:${i}`))}
                  </tbody>
                </table>
              </div>
            )}

            {!loading && <div className="-mx-4 -mb-4 mt-4"><LazyFooter lazy={lazy} total={displayRows.length} /></div>}
          </div>
        </div>
      )}

      {/* ── No active report placeholder ───────────────────────────────── */}
      {!activeId && (
        <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 p-8 flex flex-col items-center justify-center gap-3 text-slate-400 dark:text-zinc-600">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 text-slate-200 dark:text-zinc-800" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
          <p className="text-sm">Select a report type above to generate a preview.</p>
        </div>
      )}
    </MainLayout>
  )
}

export default Reports
