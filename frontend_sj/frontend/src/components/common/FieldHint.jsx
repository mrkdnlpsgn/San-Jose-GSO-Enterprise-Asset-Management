function FieldHint({ text, placement = 'center' }) {
  const tooltipPos = placement === 'left'
    ? 'right-0 bottom-full mb-2.5'
    : 'left-1/2 -translate-x-1/2 bottom-full mb-2.5'

  const arrowPos = placement === 'left'
    ? 'right-3 top-full border-t-zinc-800'
    : 'left-1/2 -translate-x-1/2 top-full border-t-zinc-800'

  return (
    <span className="relative group inline-flex items-center ml-1.5 align-middle">
      <button
        type="button"
        tabIndex={0}
        aria-label={text}
        className="w-3.5 h-3.5 rounded-full bg-slate-200 dark:bg-zinc-700 text-slate-500 dark:text-zinc-400 text-[0.5625rem] font-bold flex items-center justify-center cursor-default select-none leading-none focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:ring-offset-white dark:focus:ring-offset-zinc-900"
      >
        ?
      </button>
      <span
        role="tooltip"
        className={`
          absolute ${tooltipPos}
          w-56 px-3 py-2.5 rounded-lg
          bg-zinc-800 border border-zinc-700
          text-xs text-zinc-200 leading-relaxed font-normal normal-case tracking-normal
          shadow-xl
          opacity-0 group-hover:opacity-100 group-focus-within:opacity-100
          transition-opacity duration-150
          pointer-events-none z-[200]
          whitespace-normal text-left
        `}
      >
        {text}
        <span className={`absolute border-4 border-transparent ${arrowPos}`} />
      </span>
    </span>
  )
}

export default FieldHint
