import { useState, useRef, useMemo } from 'react'
import * as XLSX from 'xlsx'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import { useToast } from '../../context/ToastContext'
import api from '../../services/api'
import { getAssetHistory } from '../../services/assetHistoryService'

// Reports need the full dataset, not a paginated page. getAssets()/getDisposal()/getMaintenance()
// default to the backend's page size of 20 — fine for list pages, wrong here, so fetch directly
// with a size large enough to always cover a single municipal office's inventory in one page.
const getAllAssets     = () => api.get('/assets', { params: { size: 100000 } })
const getAllDisposal   = () => api.get('/disposal', { params: { size: 100000 } })
const getAllMaintenance = () => api.get('/maintenance', { params: { size: 100000 } })

// ── Formatters ────────────────────────────────────────────────────────────────
const fmtDate = (d) =>
  d ? new Date(d).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' }) : '—'
const fmtMoney = (v) =>
  v != null && v !== '' ? '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 }) : '—'
const fmtDateTime = (dt) =>
  dt ? new Date(dt).toLocaleString('en-PH', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'
const esc = (s) => String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

// ── Date filtering ────────────────────────────────────────────────────────────
// With thousands of assets, reports default to unbounded — this lets a user
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
    const d = String(v).slice(0, 10)
    if (from && d < from) return false
    if (to && d > to) return false
    return true
  })
}

// RPCPPE physical-count variance: quantity per records vs. quantity per physical count.
// physicalCount is null until someone has actually counted the asset — don't assume a shortage.
const assetVariance = (r) => {
  if (r.physicalCount == null) return null
  return Number(r.physicalCount) - Number(r.quantity ?? 1)
}
const fmtVariance = (r) => {
  const v = assetVariance(r)
  if (v === null) return 'Not yet counted'
  if (v === 0) return 'None'
  return v > 0 ? `+${v} (Overage)` : `${v} (Shortage)`
}
const varianceValue = (r) => {
  const v = assetVariance(r)
  return v === null ? 0 : v * (Number(r.unitValue) || 0)
}

// ── Report definitions ────────────────────────────────────────────────────────
const REPORTS = [
  {
    id: 'inventory',
    title: 'Asset Inventory',
    description: 'Complete list of all ICT assets with condition, lifecycle status, and location.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path d="M9 2a1 1 0 000 2h2a1 1 0 100-2H9z" />
        <path fillRule="evenodd" d="M4 5a2 2 0 012-2 3 3 0 003 3h2a3 3 0 003-3 2 2 0 012 2v11a2 2 0 01-2 2H6a2 2 0 01-2-2V5zm3 4a1 1 0 000 2h.01a1 1 0 100-2H7zm3 0a1 1 0 000 2h3a1 1 0 100-2h-3zm-3 4a1 1 0 100 2h.01a1 1 0 100-2H7zm3 0a1 1 0 100 2h3a1 1 0 100-2h-3z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getAllAssets()).data
    },
    dateField: 'acquisitionDate',
    headers: [
      { label: 'Property No.',    display: (r) => <span className="font-mono text-xs">{r.propertyNumber || '—'}</span>,                                   raw: (r) => r.propertyNumber || '' },
      { label: 'Description',     display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.description || '—'}</span>,              raw: (r) => r.description || '' },
      { label: 'Category',        display: (r) => r.category?.categoryName || '—',                                                                        raw: (r) => r.category?.categoryName || '' },
      { label: 'Condition',       display: (r) => r.condition || '—',                                                                                     raw: (r) => r.condition || '' },
      { label: 'Lifecycle',       display: (r) => (r.lifecycleStatus || '').replace('_', ' ') || '—',                                                     raw: (r) => r.lifecycleStatus || '' },
      { label: 'Office',          display: (r) => r.office?.officeName || '—',                                                                            raw: (r) => r.office?.officeName || '' },
      { label: 'Location',        display: (r) => r.location || '—',                                                                                      raw: (r) => r.location || '' },
      { label: 'Accountable',     display: (r) => r.accountablePerson?.fullName || r.accountablePerson?.username || '—',                                  raw: (r) => r.accountablePerson?.fullName || r.accountablePerson?.username || '' },
      { label: 'Qty',             display: (r) => r.quantity ?? 1,                                                                                        raw: (r) => r.quantity ?? 1 },
      { label: 'Unit Value',      display: (r) => fmtMoney(r.unitValue),                                                                                  raw: (r) => r.unitValue != null ? Number(r.unitValue).toFixed(2) : '' },
      { label: 'Acq. Date',       display: (r) => fmtDate(r.acquisitionDate),                                                                             raw: (r) => r.acquisitionDate || '' },
    ],
  },
  {
    id: 'condition',
    title: 'Condition Report',
    description: 'Asset breakdown by condition — serviceable, repairable, and unserviceable counts.',
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
        .map((r) => ({ ...r, offices: [...r.offices].join(', ') || '—' }))
    },
    headers: [
      { label: 'Condition',       display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.condition}</span>,                      raw: (r) => r.condition },
      { label: 'Count',           display: (r) => <span className="font-semibold text-brand-400">{r.count}</span>,                                        raw: (r) => r.count },
      { label: 'Total Value (₱)', display: (r) => r.totalValue > 0 ? fmtMoney(r.totalValue) : '—',                                                       raw: (r) => r.totalValue > 0 ? r.totalValue.toFixed(2) : '' },
      { label: 'Offices',         display: (r) => <span className="text-slate-400 dark:text-zinc-400 text-xs">{r.offices}</span>,                         raw: (r) => r.offices },
    ],
  },
  {
    id: 'history',
    title: 'Asset History',
    description: 'Full log of all asset events — assignments, transfers, maintenance, and disposals.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getAssetHistory()).data
    },
    dateField: 'eventDate',
    headers: [
      { label: 'Asset',           display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.asset?.description || '—'}</span>,       raw: (r) => r.asset?.description || '' },
      { label: 'Property No.',    display: (r) => <span className="font-mono text-xs">{r.asset?.propertyNumber || '—'}</span>,                             raw: (r) => r.asset?.propertyNumber || '' },
      { label: 'Event Type',      display: (r) => r.eventType || '—',                                                                                     raw: (r) => r.eventType || '' },
      { label: 'From Office',     display: (r) => r.fromOffice?.officeName || '—',                                                                        raw: (r) => r.fromOffice?.officeName || '' },
      { label: 'To Office',       display: (r) => r.toOffice?.officeName || '—',                                                                          raw: (r) => r.toOffice?.officeName || '' },
      { label: 'Performed By',    display: (r) => r.performedBy?.fullName || r.performedBy?.username || '—',                                              raw: (r) => r.performedBy?.fullName || r.performedBy?.username || '' },
      { label: 'Notes',           display: (r) => r.notes ? <span className="max-w-[160px] truncate block" title={r.notes}>{r.notes}</span> : '—',        raw: (r) => r.notes || '' },
      { label: 'Date',            display: (r) => <span className="text-xs whitespace-nowrap">{fmtDate(r.eventDate)}</span>,                              raw: (r) => r.eventDate || '' },
    ],
  },
  {
    id: 'valuation',
    title: 'Asset Valuation',
    description: 'Financial summary of ICT asset acquisition values, sorted by unit value.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path d="M2 11a1 1 0 011-1h2a1 1 0 011 1v5a1 1 0 01-1 1H3a1 1 0 01-1-1v-5zM8 7a1 1 0 011-1h2a1 1 0 011 1v9a1 1 0 01-1 1H9a1 1 0 01-1-1V7zM14 4a1 1 0 011-1h2a1 1 0 011 1v12a1 1 0 01-1 1h-2a1 1 0 01-1-1V4z" />
      </svg>
    ),
    async load() {
      return (await getAllAssets()).data
    },
    dateField: 'acquisitionDate',
    transform(assets) {
      return assets
        .filter((a) => a.unitValue != null && a.unitValue !== '')
        .sort((a, b) => Number(b.unitValue) - Number(a.unitValue))
    },
    extraRows: (rows) => {
      const total = rows.reduce((s, r) => s + (Number(r.unitValue) || 0) * (Number(r.quantity) || 1), 0)
      return [
        ...rows,
        {
          propertyNumber: 'TOTAL ACQUISITION VALUE',
          description: '', category: null, condition: '', lifecycleStatus: '',
          unitValue: total, quantity: 1, acquisitionDate: '', office: null,
          location: '', accountablePerson: null, remarks: '',
        },
      ]
    },
    headers: [
      { label: 'Property No.',    display: (r) => <span className="font-mono text-xs">{r.propertyNumber || '—'}</span>,                                   raw: (r) => r.propertyNumber || '' },
      { label: 'Description',     display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.description || '—'}</span>,              raw: (r) => r.description || '' },
      { label: 'Category',        display: (r) => r.category?.categoryName || '—',                                                                        raw: (r) => r.category?.categoryName || '' },
      { label: 'Condition',       display: (r) => r.condition || '—',                                                                                     raw: (r) => r.condition || '' },
      { label: 'Unit Value',      display: (r) => <span className="font-semibold text-amber-400">{fmtMoney(r.unitValue)}</span>,                          raw: (r) => Number(r.unitValue).toFixed(2) },
      { label: 'Quantity',        display: (r) => r.quantity ?? 1,                                                                                        raw: (r) => r.quantity ?? 1 },
      { label: 'Total Value',     display: (r) => fmtMoney((Number(r.unitValue) || 0) * (Number(r.quantity) || 1)),                                       raw: (r) => ((Number(r.unitValue) || 0) * (Number(r.quantity) || 1)).toFixed(2) },
      { label: 'Acq. Date',       display: (r) => fmtDate(r.acquisitionDate),                                                                             raw: (r) => r.acquisitionDate || '' },
      { label: 'Office',          display: (r) => r.office?.officeName || '—',                                                                            raw: (r) => r.office?.officeName || '' },
    ],
  },
  {
    id: 'maintenance',
    title: 'Maintenance Ledger',
    description: 'All maintenance and repair records for ICT assets.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getAllMaintenance()).data
    },
    dateField: 'maintenanceDate',
    headers: [
      { label: 'Asset',           display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.asset?.description || '—'}</span>,       raw: (r) => r.asset?.description || '' },
      { label: 'Type',            display: (r) => r.maintenanceType || '—',                                                                               raw: (r) => r.maintenanceType || '' },
      { label: 'Findings',        display: (r) => r.findings ? <span className="max-w-[180px] truncate block" title={r.findings}>{r.findings}</span> : '—', raw: (r) => r.findings || '' },
      { label: 'Status',          display: (r) => r.status || '—',                                                                                        raw: (r) => r.status || '' },
      { label: 'Assigned To',     display: (r) => r.assignedTo?.fullName || r.assignedTo?.username || '—',                                                raw: (r) => r.assignedTo?.fullName || r.assignedTo?.username || '' },
      { label: 'Cost',            display: (r) => r.cost != null ? fmtMoney(r.cost) : '—',                                                               raw: (r) => r.cost != null ? Number(r.cost).toFixed(2) : '' },
      { label: 'Date',            display: (r) => fmtDate(r.maintenanceDate),                                                                             raw: (r) => r.maintenanceDate || '' },
      { label: 'Recorded By',     display: (r) => r.recordedBy?.fullName || r.recordedBy?.username || '—',                                               raw: (r) => r.recordedBy?.fullName || r.recordedBy?.username || '' },
    ],
  },
  {
    id: 'rpcppe',
    title: 'RPCPPE (Physical Count)',
    description: 'COA-format Report on the Physical Count of Property, Plant and Equipment — records vs. physical count variance.',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M6 2a2 2 0 00-2 2v12a2 2 0 002 2h8a2 2 0 002-2V7.914a2 2 0 00-.586-1.414l-3.914-3.914A2 2 0 0010.086 2H6zm.5 8a.5.5 0 000 1h7a.5.5 0 000-1h-7zm0 3a.5.5 0 000 1h4a.5.5 0 000-1h-4z" clipRule="evenodd" />
      </svg>
    ),
    async load() {
      return (await getAllAssets()).data
    },
    dateField: 'acquisitionDate',
    headers: [
      { label: 'Article',             display: (r) => r.category?.categoryName || '—',                                                                    raw: (r) => r.category?.categoryName || '' },
      { label: 'Description',         display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.description || '—'}</span>,          raw: (r) => r.description || '' },
      { label: 'Property No.',        display: (r) => <span className="font-mono text-xs">{r.propertyNumber || '—'}</span>,                                raw: (r) => r.propertyNumber || '' },
      { label: 'Unit Value',          display: (r) => fmtMoney(r.unitValue),                                                                              raw: (r) => r.unitValue != null ? Number(r.unitValue).toFixed(2) : '' },
      { label: 'Qty per Records',     display: (r) => r.quantity ?? 1,                                                                                    raw: (r) => r.quantity ?? 1 },
      { label: 'Qty per Phys. Count', display: (r) => r.physicalCount ?? '—',                                                                             raw: (r) => r.physicalCount ?? '' },
      { label: 'Shortage/Overage',    display: (r) => fmtVariance(r),                                                                                      raw: (r) => fmtVariance(r) },
      { label: 'Value of Variance',   display: (r) => varianceValue(r) !== 0 ? fmtMoney(varianceValue(r)) : '—',                                           raw: (r) => varianceValue(r).toFixed(2) },
      { label: 'Location',            display: (r) => r.location || '—',                                                                                  raw: (r) => r.location || '' },
      { label: 'Condition',           display: (r) => r.condition || '—',                                                                                 raw: (r) => r.condition || '' },
      { label: 'Remarks',             display: (r) => r.remarks || '—',                                                                                   raw: (r) => r.remarks || '' },
    ],
    certification: [
      'Prepared by: Property Custodian / GSO Staff',
      'Certified Correct by: Inventory Committee Chairman',
      'Member, Inventory Committee',
      'Member, Inventory Committee',
      'Verified by: COA Representative',
    ],
  },
  {
    id: 'iirup',
    title: 'IIRUP (Unserviceable Property)',
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
      { label: 'Date Acquired',                 display: (r) => fmtDate(r.asset?.acquisitionDate),                                                                raw: (r) => r.asset?.acquisitionDate || '' },
      { label: 'Particulars/Article',           display: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.asset?.description || '—'}</span>, raw: (r) => r.asset?.description || '' },
      { label: 'Property No.',                  display: (r) => <span className="font-mono text-xs">{r.asset?.propertyNumber || '—'}</span>,                     raw: (r) => r.asset?.propertyNumber || '' },
      { label: 'Qty.',                          display: (r) => r.asset?.quantity ?? 1,                                                                           raw: (r) => r.asset?.quantity ?? 1 },
      { label: 'Unit Cost',                     display: (r) => fmtMoney(r.asset?.unitValue),                                                                     raw: (r) => r.asset?.unitValue != null ? Number(r.asset.unitValue).toFixed(2) : '' },
      { label: 'Total Cost',                    display: (r) => fmtMoney((Number(r.asset?.unitValue) || 0) * (Number(r.asset?.quantity) || 1)),                   raw: (r) => ((Number(r.asset?.unitValue) || 0) * (Number(r.asset?.quantity) || 1)).toFixed(2) },
      { label: 'Accumulated Depreciation',      display: () => '—',                                                                                               raw: () => '' },
      { label: 'Accumulated Impairment Losses', display: () => '—',                                                                                               raw: () => '' },
      { label: 'Carrying Amount',               display: () => '—',                                                                                               raw: () => '' },
      { label: 'Remarks',                       display: (r) => r.inspectionFindings ? <span className="max-w-[180px] truncate block" title={r.inspectionFindings}>{r.inspectionFindings}</span> : '—', raw: (r) => r.inspectionFindings || '' },
      { label: 'Sale',                          display: (r) => r.recommendedMethod === 'AUCTION'   ? (r.asset?.quantity ?? 1) : '—',                             raw: (r) => r.recommendedMethod === 'AUCTION'   ? (r.asset?.quantity ?? 1) : '' },
      { label: 'Transfer',                      display: (r) => r.recommendedMethod === 'TRANSFER'  ? (r.asset?.quantity ?? 1) : '—',                             raw: (r) => r.recommendedMethod === 'TRANSFER'  ? (r.asset?.quantity ?? 1) : '' },
      { label: 'Destruction',                   display: () => '—',                                                                                               raw: () => '' },
      { label: 'Others (Specify)',              display: (r) => r.recommendedMethod === 'DONATION'  ? 'Donation' : '—',                                           raw: (r) => r.recommendedMethod === 'DONATION'  ? 'Donation' : '' },
      { label: 'Total',                         display: (r) => r.asset?.quantity ?? 1,                                                                           raw: (r) => r.asset?.quantity ?? 1 },
      { label: 'Appraised Value',               display: (r) => fmtMoney(r.appraisedValue),                                                                       raw: (r) => r.appraisedValue != null ? Number(r.appraisedValue).toFixed(2) : '' },
      { label: 'OR No.',                        display: (r) => r.orNumber || '—',                                                                                raw: (r) => r.orNumber || '' },
      { label: 'Amount',                        display: (r) => fmtMoney(r.amount),                                                                               raw: (r) => r.amount != null ? Number(r.amount).toFixed(2) : '' },
    ],
    certification: [
      'Inspected by: GSO Inspector',
      'Certified Correct by: Inventory Committee Chairman',
      'Recommending Approval: Head of Office',
      'Approved by: Local Chief Executive (Municipal Mayor)',
    ],
  },
]

// ── Export helpers ────────────────────────────────────────────────────────────
function exportExcel(rows, headers, title) {
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
  XLSX.utils.book_append_sheet(wb, ws, title.slice(0, 31))
  XLSX.writeFile(wb, `${title.replace(/\s+/g, '_')}_${new Date().toISOString().slice(0, 10)}.xlsx`)
}

function exportPDF(rows, headers, title, certification) {
  const headerCells = headers.map((h) => `<th>${esc(h.label)}</th>`).join('')
  const bodyRows = rows.map((row) =>
    `<tr>${headers.map(({ raw }) => `<td>${esc(raw(row)) || '—'}</td>`).join('')}</tr>`
  ).join('')

  const certifyBlock = certification?.length ? `
  <div class="certify">
    ${certification.map((role) => `
    <div class="sig-block">
      <div class="sig-line"></div>
      <p class="sig-role">${esc(role)}</p>
    </div>`).join('')}
  </div>` : ''

  const html = `<!DOCTYPE html>
<html>
<head>
  <title>${esc(title)}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', Arial, sans-serif; font-size: 11px; padding: 28px; color: #111827; }
    .header { margin-bottom: 18px; border-bottom: 2px solid #e5e7eb; padding-bottom: 12px; }
    .header h1 { font-size: 18px; font-weight: 700; color: #111827; }
    .header p  { font-size: 10px; color: #6b7280; margin-top: 3px; }
    table  { width: 100%; border-collapse: collapse; font-size: 10px; }
    th     { background: #f9fafb; text-align: left; padding: 7px 8px; font-weight: 600; font-size: 9px; text-transform: uppercase; letter-spacing: .05em; border: 1px solid #e5e7eb; color: #374151; }
    td     { padding: 5px 8px; border: 1px solid #e5e7eb; vertical-align: top; color: #374151; }
    tr:nth-child(even) td { background: #f9fafb; }
    .footer { margin-top: 16px; font-size: 9px; color: #9ca3af; border-top: 1px solid #f3f4f6; padding-top: 8px; }
    .certify { display: flex; flex-wrap: wrap; gap: 32px; margin-top: 48px; page-break-inside: avoid; }
    .sig-block { width: 200px; }
    .sig-line { border-bottom: 1px solid #111827; height: 36px; }
    .sig-role { font-size: 9px; text-align: center; margin-top: 4px; color: #374151; }
    @media print { body { padding: 0; } }
  </style>
</head>
<body>
  <div class="header">
    <h1>${esc(title)}</h1>
    <p>San Jose Municipal Hall &middot; GSO Inventory Management System &middot; Generated: ${new Date().toLocaleString('en-PH')} &middot; ${rows.length} record(s)</p>
  </div>
  <table>
    <thead><tr>${headerCells}</tr></thead>
    <tbody>${bodyRows}</tbody>
  </table>
  ${certifyBlock}
  <p class="footer">This is a system-generated report. &copy; ${new Date().getFullYear()} San Jose Municipal Hall.</p>
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
</body>
</html>`

  const win = window.open('', '_blank', 'width=1100,height=800')
  win.document.write(html)
  win.document.close()
}

// ── Totals row for valuation report ──────────────────────────────────────────
function ValuationTotalsRow({ rows }) {
  const total = rows.reduce((s, r) => s + (Number(r.unitValue) || 0) * (Number(r.quantity) || 1), 0)
  return (
    <tr className="border-t-2 border-slate-200 dark:border-zinc-700 bg-slate-50 dark:bg-zinc-800/60">
      <td className="px-4 py-3 text-sm font-bold text-slate-900 dark:text-white" colSpan={6}>Total</td>
      <td className="px-4 py-3 text-sm font-bold text-amber-400">{fmtMoney(total)}</td>
      <td className="px-4 py-3" colSpan={2} />
    </tr>
  )
}

// ── Date range filter ─────────────────────────────────────────────────────────
const PAGE_SIZE = 8

const DATE_INPUT_CLASS ='rounded-md border border-slate-200 dark:border-zinc-700 px-2.5 py-1.5 text-xs bg-white dark:bg-zinc-800 text-slate-700 dark:text-zinc-200 hover:border-slate-300 dark:hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150 [color-scheme:light] dark:[color-scheme:dark]'

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
        <input type="date" value={from} max={to || undefined} onChange={(e) => onChange({ from: e.target.value, to })} className={DATE_INPUT_CLASS} />
        <span className="text-2xs text-slate-400 dark:text-zinc-600">to</span>
        <input type="date" value={to} min={from || undefined} onChange={(e) => onChange({ from, to: e.target.value })} className={DATE_INPUT_CLASS} />
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

// ── Component ─────────────────────────────────────────────────────────────────
function Reports() {
  const { show } = useToast()

  const [activeId, setActiveId]     = useState(null)
  const [reportData, setReportData] = useState([])
  const [loading, setLoading]       = useState(false)
  const [dateFrom, setDateFrom]     = useState('')
  const [dateTo, setDateTo]         = useState('')
  const [page, setPage]             = useState(1)
  const previewRef = useRef(null)

  const activeReport = REPORTS.find((r) => r.id === activeId)

  const handleDateChange = ({ from, to }) => { setDateFrom(from); setDateTo(to); setPage(1) }

  const handleGenerate = async (report) => {
    if (activeId === report.id) {
      setActiveId(null)
      setReportData([])
      setDateFrom('')
      setDateTo('')
      setPage(1)
      return
    }
    setLoading(true)
    setActiveId(report.id)
    setReportData([])
    setDateFrom('')
    setDateTo('')
    setPage(1)
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

  // Date filter runs on the raw loaded rows first, then any per-report
  // aggregation (`transform`, e.g. the Condition Report's grouping) runs on
  // top of that — so filtering a range re-aggregates instead of just hiding rows.
  const displayRows = useMemo(() => {
    if (!activeReport) return []
    const filtered = applyDateFilter(reportData, activeReport.dateField, dateFrom, dateTo)
    return activeReport.transform ? activeReport.transform(filtered) : filtered
  }, [reportData, activeReport, dateFrom, dateTo])

  const isDateFiltered = Boolean(dateFrom || dateTo)

  const totalPages = Math.max(1, Math.ceil(displayRows.length / PAGE_SIZE))
  const pagedRows = displayRows.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

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
                  {displayRows.length} {displayRows.length === 1 ? 'record' : 'records'}
                  {isDateFiltered && !activeReport?.aggregated && reportData.length !== displayRows.length && (
                    <span className="text-slate-300 dark:text-zinc-600"> (of {reportData.length})</span>
                  )}
                </p>
              )}
            </div>
            {!loading && reportData.length > 0 && (
              <div className="flex flex-wrap gap-2">
                <Button variant="secondary" size="md" onClick={() => exportExcel(getExportRows(), activeReport.headers, activeReport.title)}>
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 sm:mr-1.5 text-emerald-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
                  </svg>
                  <span className="hidden sm:inline">Export Excel</span>
                </Button>
                <Button variant="secondary" size="md" onClick={() => exportPDF(getExportRows(), activeReport.headers, activeReport.title, activeReport.certification)}>
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 sm:mr-1.5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
                  </svg>
                  <span className="hidden sm:inline">Print / PDF</span>
                </Button>
              </div>
            )}
          </div>

          {!loading && reportData.length > 0 && activeReport?.dateField && (
            <div className="px-5 py-3 border-b border-slate-200 dark:border-zinc-800 bg-slate-50/60 dark:bg-zinc-800/20">
              <DateRangeFilter from={dateFrom} to={dateTo} onChange={handleDateChange} />
            </div>
          )}

          <div className="p-4">
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
                  {reportData.length > 0 && isDateFiltered
                    ? 'No records in the selected date range.'
                    : 'No data available for this report.'}
                </p>
              </div>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-slate-200 dark:border-zinc-800">
                <table className="min-w-full text-sm divide-y divide-slate-200 dark:divide-zinc-800">
                  <thead className="bg-slate-50 dark:bg-zinc-900 sticky top-0">
                    <tr>
                      {activeReport.headers.map((h) => (
                        <th key={h.label} className="px-4 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">
                          {h.label}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="bg-white dark:bg-zinc-950 divide-y divide-slate-100 dark:divide-zinc-800/60">
                    {pagedRows.map((row, i) => (
                      <tr key={i} className="hover:bg-slate-50 dark:hover:bg-zinc-800/50 transition-colors duration-100">
                        {activeReport.headers.map((h) => (
                          <td key={h.label} className="px-4 py-3 text-slate-600 dark:text-zinc-300 whitespace-nowrap">
                            {h.display(row)}
                          </td>
                        ))}
                      </tr>
                    ))}
                    {activeId === 'valuation' && <ValuationTotalsRow rows={displayRows} />}
                  </tbody>
                </table>
              </div>
            )}

            {!loading && displayRows.length > PAGE_SIZE && (
              <div className="pt-3 flex items-center justify-between gap-3">
                <p className="text-xs text-slate-400 dark:text-zinc-500">
                  {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, displayRows.length)} of {displayRows.length}
                </p>
                <div className="flex items-center gap-1">
                  <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}
                    className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">Prev</button>
                  <span className="text-xs text-slate-400 px-2">{page} / {totalPages}</span>
                  <button onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                    className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">Next</button>
                </div>
              </div>
            )}
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
