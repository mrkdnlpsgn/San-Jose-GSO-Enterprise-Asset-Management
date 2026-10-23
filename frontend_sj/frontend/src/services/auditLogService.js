import api from './api'

export const getAuditLogs = (search = '') => search.trim()
  ? api.get('/audit-logs', { params: { search: search.trim() } })
  : api.get('/audit-logs')

// Entries older than the retention period (one year by default) are moved to an archive nightly.
export const getAuditArchiveSummary = () => api.get('/audit-logs/archive/summary')
export const runAuditArchive = () => api.post('/audit-logs/archive/run')
// CSV of archived entries; from/to are 'YYYY-MM-DD' (Philippine dates), both optional
export const exportAuditArchive = (from, to) => api.get('/audit-logs/archive/export', {
  params: { ...(from ? { from } : {}), ...(to ? { to } : {}) },
  responseType: 'blob',
})

// "Asset Health": a short AI note on the condition of the inventory and what needs action
// (admin). GET returns the latest one, or 404 when none was generated yet (its body may say AI
// is paused for the day). POST writes a new one; it uses the daily AI allowance.
export const getAssetHealth      = () => api.get('/audit-logs/digest')
export const generateAssetHealth = () => api.post('/audit-logs/digest')
