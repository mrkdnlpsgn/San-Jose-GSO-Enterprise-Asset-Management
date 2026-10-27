import { Children, Fragment, forwardRef, isValidElement, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'

// Every form dropdown in the app. Written like a plain <select> (value, onChange, <option>
// children), so pages don't change:
//  - with a mouse or trackpad it opens our own list, styled like the rest of the forms, with a
//    search box when there are many options (categories, offices, people);
//  - on touch screens it stays the browser's <select>, so phones keep their own picker.
// onChange receives an input-like event ({ target: { name, value } }), the same as DatePicker,
// so existing `set(key)` handlers keep working. `className` is the page's input style;
// `wrapperClassName` styles the box around it (a margin, flex-1 in a row). List filters use
// FilterSelect in ListKit instead.

const SEARCH_FROM = 8      // show a search box from this many options
const GAP = 6
const EDGE = 8
const MAX_LIST_HEIGHT = 288 // px, about 8 rows

const CHEVRON_PATH = 'M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z'

function ChevronIcon({ className }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" className={className}>
      <path fillRule="evenodd" d={CHEVRON_PATH} clipRule="evenodd" />
    </svg>
  )
}

// Plain text of an option's children, for searching and type-to-jump.
const textOf = (node) => {
  if (node == null || typeof node === 'boolean') return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(textOf).join('')
  return isValidElement(node) ? textOf(node.props.children) : ''
}

// The <option> elements among the children, looking inside fragments and arrays.
const optionsOf = (children) => {
  const out = []
  const walk = (nodes) => Children.forEach(nodes, (child) => {
    if (!isValidElement(child)) return
    if (child.type === Fragment) return walk(child.props.children)
    if (child.type !== 'option') return
    const text = textOf(child.props.children)
    out.push({ value: String(child.props.value ?? text), label: child.props.children, text, disabled: !!child.props.disabled })
  })
  walk(children)
  return out
}

const isTouch = () => typeof window !== 'undefined' && window.matchMedia?.('(pointer: coarse)').matches

const Select = forwardRef(function Select(props, ref) {
  return isTouch() ? <NativeSelect ref={ref} {...props} /> : <ListboxSelect {...props} />
})

// Phones and tablets: the browser's own <select> with our arrow.
const NativeSelect = forwardRef(function NativeSelect({ className = '', wrapperClassName = '', children, ...props }, ref) {
  return (
    <div className={`relative ${wrapperClassName}`}>
      <select ref={ref} className={`${className} appearance-none pr-9 cursor-pointer disabled:cursor-not-allowed`} {...props}>
        {children}
      </select>
      <ChevronIcon className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 dark:text-zinc-500" />
    </div>
  )
})

function ListboxSelect({ value, onChange, name, id, disabled = false, className = '', wrapperClassName = '', children, ...rest }) {
  const options = useMemo(() => optionsOf(children), [children])
  const current = String(value ?? '')
  const selected = options.find((o) => o.value === current) || options[0]

  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(-1)  // index into `shown`
  const [pos, setPos] = useState(null)
  const triggerRef = useRef(null)
  const popRef = useRef(null)
  const listRef = useRef(null)
  const searchRef = useRef(null)
  const typed = useRef({ text: '', at: 0 })
  const listId = useId()

  const searchable = options.length >= SEARCH_FROM
  const q = query.trim().toLowerCase()
  const shown = q ? options.filter((o) => o.text.toLowerCase().includes(q)) : options
  const optionId = (i) => `${listId}-o${i}`

  const close = (refocus = true) => {
    setOpen(false)
    setQuery('')
    setPos(null)
    if (refocus) triggerRef.current?.focus()
  }
  const choose = (o) => {
    if (!o || o.disabled) return
    if (o.value !== current) onChange?.({ target: { name, value: o.value, type: 'select-one' } })
    close()
  }
  const openList = (startQuery = '') => {
    if (disabled) return
    setQuery(startQuery)
    const start = startQuery ? 0 : Math.max(0, options.indexOf(selected))
    setActive(start)
    setOpen(true)
  }

  // Fixed-position list (not clipped by a modal's scrolling body), at least as wide as the
  // field; opens above when there's more room there, and stays inside the window.
  const place = () => {
    const r = triggerRef.current?.getBoundingClientRect()
    if (!r) return
    const vw = window.innerWidth, vh = window.innerHeight
    const width = Math.min(Math.max(r.width, 192), vw - EDGE * 2)
    const left = Math.min(Math.max(EDGE, r.left), vw - width - EDGE)
    const below = vh - r.bottom - GAP - EDGE
    const above = r.top - GAP - EDGE
    const extra = searchable ? 52 : 0
    const want = Math.min(MAX_LIST_HEIGHT, shown.length * 38 + 8) + extra
    const up = below < want && above > below
    const maxHeight = Math.max(120, Math.min(want, up ? above : below))
    setPos(up ? { bottom: vh - r.top + GAP, left, width, maxHeight } : { top: r.bottom + GAP, left, width, maxHeight })
  }

  useLayoutEffect(() => { if (open) place() }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!open) return
    // A click outside only closes the list, as with a native select: the click itself is
    // swallowed, so it can't also land on a dialog's backdrop and close the whole form.
    const onDown = (e) => {
      if (popRef.current?.contains(e.target) || triggerRef.current?.contains(e.target)) return
      const swallow = (ev) => { ev.stopPropagation(); ev.preventDefault() }
      document.addEventListener('click', swallow, { capture: true, once: true })
      setTimeout(() => document.removeEventListener('click', swallow, { capture: true }), 600)
      close(false)
    }
    // Capture phase, like DatePicker: Escape closes only this list, never the dialog around it.
    const onEsc = (e) => {
      if (e.key !== 'Escape') return
      e.stopImmediatePropagation()
      e.preventDefault()
      close()
    }
    // Scrolling the page moves the field; scrolling inside the list doesn't.
    const onScroll = (e) => { if (!popRef.current?.contains(e.target)) place() }
    window.addEventListener('resize', place)
    window.addEventListener('scroll', onScroll, true)
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onEsc, true)
    return () => {
      window.removeEventListener('resize', place)
      window.removeEventListener('scroll', onScroll, true)
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onEsc, true)
    }
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  // Once placed (it renders hidden until then, and hidden elements can't take focus): focus
  // the search box, or the list itself, and keep the highlighted option in view.
  const placed = pos != null
  useEffect(() => {
    if (open && placed) (searchRef.current || listRef.current)?.focus()
  }, [open, placed])

  useEffect(() => {
    if (open && pos) listRef.current?.querySelector(`#${CSS.escape(optionId(active))}`)?.scrollIntoView({ block: 'nearest' })
  }, [open, pos, active]) // eslint-disable-line react-hooks/exhaustive-deps

  // A new search starts at the first match.
  useEffect(() => { if (open) setActive(shown.findIndex((o) => !o.disabled)) }, [query]) // eslint-disable-line react-hooks/exhaustive-deps

  const move = (from, step) => {
    if (!shown.length) return -1
    let i = from
    for (let n = 0; n < shown.length; n++) {
      i = Math.min(shown.length - 1, Math.max(0, i + step))
      if (!shown[i].disabled) return i
      if (i === 0 || i === shown.length - 1) break
    }
    return from
  }

  const onListKey = (e) => {
    const keys = {
      ArrowDown: () => move(active, 1),
      ArrowUp: () => move(active, -1),
      PageDown: () => Math.min(shown.length - 1, active + 7),
      PageUp: () => Math.max(0, active - 7),
      Home: () => move(-1, 1),
      End: () => move(shown.length, -1),
    }
    if (keys[e.key] && !(searchable && (e.key === 'Home' || e.key === 'End'))) {
      e.preventDefault()
      setActive(keys[e.key]())
    } else if (e.key === 'Enter' || (e.key === ' ' && !searchable)) {
      e.preventDefault()
      choose(shown[active])
    } else if (e.key === 'Tab') {
      // Back to the field first, so the Tab itself moves on to the next field as usual
      // (the list lives at the end of the page, outside the form's tab order).
      close()
    } else if (!searchable && e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
      // Type-to-jump, as in a native select: letters typed within a second add up.
      const now = Date.now()
      const text = (now - typed.current.at < 1000 ? typed.current.text : '') + e.key.toLowerCase()
      typed.current = { text, at: now }
      const hit = shown.findIndex((o) => !o.disabled && o.text.toLowerCase().startsWith(text))
      if (hit >= 0) setActive(hit)
    }
  }

  const onTriggerKey = (e) => {
    if (['ArrowDown', 'ArrowUp', 'Enter', ' '].includes(e.key)) {
      e.preventDefault()
      openList()
    } else if (searchable && e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault()
      openList(e.key)
    }
  }

  const isPlaceholder = selected?.value === ''

  return (
    <div className={`relative ${wrapperClassName}`}>
      <button
        ref={triggerRef}
        id={id}
        type="button"
        disabled={disabled}
        onClick={() => (open ? close() : openList())}
        onKeyDown={onTriggerKey}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listId : undefined}
        aria-required={rest['aria-required']}
        className={`${className} flex items-center justify-between gap-2 text-left cursor-pointer disabled:cursor-not-allowed`}
      >
        <span className={`truncate min-w-0 ${isPlaceholder ? 'text-slate-500 dark:text-zinc-400' : ''}`}>{selected?.label ?? ''}</span>
        <ChevronIcon className={`h-4 w-4 shrink-0 text-slate-400 dark:text-zinc-500 transition-transform duration-150 ${open ? 'rotate-180' : ''}`} />
      </button>

      {open && createPortal(
        <div
          ref={popRef}
          onKeyDown={onListKey}
          style={pos ? { top: pos.top, bottom: pos.bottom, left: pos.left, width: pos.width, maxHeight: pos.maxHeight } : { visibility: 'hidden', top: 0, left: 0 }}
          className="fixed z-[60] flex flex-col rounded-lg bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 shadow-xl shadow-black/15 dark:shadow-black/60 overflow-hidden"
        >
          {searchable && (
            <div className="p-2 border-b border-slate-100 dark:border-zinc-800 shrink-0">
              <input
                ref={searchRef}
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search"
                aria-label="Search the options"
                aria-controls={listId}
                aria-activedescendant={active >= 0 ? optionId(active) : undefined}
                className="w-full rounded-md border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3 py-2 text-sm text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
              />
            </div>
          )}
          <ul
            ref={listRef}
            id={listId}
            role="listbox"
            tabIndex={searchable ? -1 : 0}
            aria-labelledby={id}
            aria-activedescendant={!searchable && active >= 0 ? optionId(active) : undefined}
            className="flex-1 overflow-y-auto py-1 focus:outline-none"
            style={{ scrollbarWidth: 'thin' }}
          >
            {shown.length === 0 && (
              <li className="px-3.5 py-2 text-sm text-slate-500 dark:text-zinc-400">No matches</li>
            )}
            {shown.map((o, i) => {
              // The empty "Select ..." line is a prompt, not a choice: no tick, no green.
              const isSelected = o.value === selected?.value && o.value !== ''
              return (
                <li
                  key={`${o.value}-${i}`}
                  id={optionId(i)}
                  role="option"
                  aria-selected={isSelected}
                  aria-disabled={o.disabled || undefined}
                  onMouseDown={(e) => e.preventDefault()}
                  onMouseMove={() => { if (!o.disabled && active !== i) setActive(i) }}
                  onClick={() => choose(o)}
                  className={`mx-1 flex items-center gap-2 rounded-md px-2.5 py-2 text-sm select-none ${
                    o.disabled
                      ? 'text-slate-400 dark:text-zinc-600 cursor-not-allowed'
                      : `cursor-pointer ${i === active ? 'bg-brand-50 dark:bg-brand-500/15' : ''} ${
                          isSelected ? 'font-medium text-brand-700 dark:text-brand-300'
                            : o.value === '' ? 'text-slate-500 dark:text-zinc-400'
                              : 'text-slate-800 dark:text-zinc-200'}`
                  }`}
                >
                  <span className="flex-1 min-w-0 break-words">{o.label}</span>
                  {isSelected && (
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" className="h-4 w-4 shrink-0">
                      <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                    </svg>
                  )}
                </li>
              )
            })}
          </ul>
        </div>,
        document.body
      )}
    </div>
  )
}

export default Select
