import { useCallback, useEffect, useRef, useState } from 'react'
import { useSelector } from 'react-redux'

// Keeps an unsaved form in localStorage so closing a modal (or the tab) doesn't lose
// what was typed. Drafts are per signed-in user and per form/record, expire after a
// week, and are thrown away if the record changed since the draft was written.
//
//   const draft = useFormDraft(`asset:${initial?.id ?? 'new'}`, form, setForm, { omit: ['password'] })
//   ...after a successful save: draft.clear()
//   <DraftNotice draft={draft} />
//
// `title` (string or fn of the form) names the draft in the module's table, where
// useDraftList + <DraftRows> list it so it can be picked up without reopening the form.
const PREFIX = 'gso-draft:'
const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000
// Forms adjust their own fields in effects right after opening (e.g. the account form
// turns 2-step off when there's no email). Wait that out before taking the "untouched"
// snapshot, or those adjustments would look like typing and leave an empty draft behind.
const SETTLE_MS = 150

const strip = (value, omit) => {
  if (!omit.length || value === null || typeof value !== 'object') return value
  const copy = { ...value }
  omit.forEach((k) => { delete copy[k] })
  return copy
}

const read = (key) => {
  try { return JSON.parse(localStorage.getItem(key)) } catch { return null }
}
// Same-tab listeners (the table's draft rows) don't get the `storage` event, so announce changes.
const CHANGED = 'gso-drafts-changed'
const announce = () => window.dispatchEvent(new Event(CHANGED))

const write = (key, entry) => {
  try { localStorage.setItem(key, JSON.stringify(entry)); announce() } catch { /* storage full or blocked — drafts are best-effort */ }
}
const remove = (key) => {
  try {
    if (localStorage.getItem(key) === null) return
    localStorage.removeItem(key); announce()
  } catch { /* ignore */ }
}

export function useFormDraft(name, value, setValue, { omit = [], enabled = true, title } = {}) {
  const userId = useSelector((s) => s.auth.user?.id)
  const storageKey = userId != null ? `${PREFIX}${userId}:${name}` : null
  const active = enabled && storageKey != null

  // `version` identifies the record as loaded (stale-draft check); `base` is the settled,
  // untouched form (is-there-anything-to-save check).
  const versionRef = useRef(JSON.stringify(strip(value, omit)))
  const baseRef    = useRef(null)
  const initialRef = useRef(value)
  const latestRef  = useRef(value)
  const clearedRef = useRef(false)
  const titleRef   = useRef(title)
  titleRef.current = title
  const [restoredAt, setRestoredAt] = useState(null)

  latestRef.current = value

  const persist = useCallback((current) => {
    if (!active || clearedRef.current || baseRef.current === null) return
    const data = strip(current, omit)
    if (JSON.stringify(data) === baseRef.current) { remove(storageKey); return }
    const t = titleRef.current
    write(storageKey, { data, version: versionRef.current, savedAt: Date.now(), title: (typeof t === 'function' ? t(current) : t) || '' })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, storageKey])

  // Settle, then restore any saved draft.
  useEffect(() => {
    if (!active) return
    const t = setTimeout(() => {
      baseRef.current = JSON.stringify(strip(latestRef.current, omit))
      const saved = read(storageKey)
      if (!saved) return
      if (Date.now() - saved.savedAt > MAX_AGE_MS || saved.version !== versionRef.current) { remove(storageKey); return }
      setValue((prev) => (prev !== null && typeof prev === 'object' ? { ...prev, ...saved.data } : saved.data))
      setRestoredAt(saved.savedAt)
    }, SETTLE_MS)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [storageKey])

  // Save shortly after typing stops…
  useEffect(() => {
    const t = setTimeout(() => persist(value), 400)
    return () => clearTimeout(t)
  }, [value, persist])

  // …and immediately when the form closes, so a quick close doesn't lose the last keystrokes.
  useEffect(() => () => persist(latestRef.current), [persist])

  // Call after a successful save — the form's contents are now the real record.
  const clear = useCallback(() => {
    clearedRef.current = true
    if (storageKey) remove(storageKey)
  }, [storageKey])

  const discard = useCallback(() => {
    if (storageKey) remove(storageKey)
    setValue(initialRef.current)
    setRestoredAt(null)
  }, [storageKey, setValue])

  return { restoredAt, clear, discard }
}

// Drafts for one module (`namespace` is the part before the record id, e.g. 'asset'),
// newest first: [{ key, id: 'new' | '<record id>', title, data, savedAt }].
export function useDraftList(namespace) {
  const userId = useSelector((s) => s.auth.user?.id)
  const prefix = userId != null ? `${PREFIX}${userId}:${namespace}:` : null

  const load = useCallback(() => {
    if (!prefix) return []
    const out = []
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i)
        if (!key?.startsWith(prefix)) continue
        const entry = read(key)
        if (!entry || Date.now() - entry.savedAt > MAX_AGE_MS) continue
        out.push({ key, id: key.slice(prefix.length), title: entry.title, data: entry.data || {}, savedAt: entry.savedAt })
      }
    } catch { /* storage blocked — no drafts to show */ }
    return out.sort((a, b) => b.savedAt - a.savedAt)
  }, [prefix])

  const [drafts, setDrafts] = useState(load)

  useEffect(() => {
    const refresh = () => setDrafts(load())
    refresh()
    window.addEventListener(CHANGED, refresh)
    window.addEventListener('storage', refresh)
    return () => { window.removeEventListener(CHANGED, refresh); window.removeEventListener('storage', refresh) }
  }, [load])

  const discard = useCallback((key) => remove(key), [])

  return { drafts, discard }
}
