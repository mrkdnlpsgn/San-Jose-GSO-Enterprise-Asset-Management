export function escapeHtml(str) {
  if (str == null) return ''
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

export const formatDate = (dateString) => {
  if (!dateString) return '—'
  return new Date(dateString).toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

// The Philippine calendar date ("YYYY-MM-DD") of a server value. Date-times arrive as UTC
// instants ("2026-10-07T17:30:00Z" is already Oct 8 in Manila), so slicing the string would give
// the wrong day between midnight and 8 AM. Plain dates ("2026-10-07") are returned as they are.
export function manilaDateKey(value) {
  if (!value) return ''
  const s = String(value)
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s
  const d = new Date(s)
  if (isNaN(d)) return s.slice(0, 10)
  return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' })   // en-CA formats as YYYY-MM-DD
}

// "2026-10-07 13:43" in Philippine time — for spreadsheet exports, where a readable local
// date-time is wanted rather than a UTC instant.
export function manilaDateTime(value) {
  if (!value) return ''
  const d = new Date(value)
  if (isNaN(d)) return String(value)
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(d).map((p) => [p.type, p.value]))
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`
}

export const capitalize = (str) =>
  str ? str.charAt(0).toUpperCase() + str.slice(1).toLowerCase() : ''

