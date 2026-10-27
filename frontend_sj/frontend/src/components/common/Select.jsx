import { forwardRef } from 'react'

// Every form dropdown in the app. It is the browser's own <select>, so the keyboard, screen
// readers and the phone's picker work as usual; only the arrow is drawn here, so it looks the
// same in every browser. `className` is the page's input style (border, padding, focus ring);
// this adds room for the arrow. `wrapperClassName` styles the box around it, e.g. a margin or
// flex-1 in a row. List filters use FilterSelect in ListKit instead.
const Select = forwardRef(function Select({ className = '', wrapperClassName = '', children, ...props }, ref) {
  return (
    <div className={`relative ${wrapperClassName}`}>
      <select ref={ref} className={`${className} appearance-none pr-9 cursor-pointer disabled:cursor-not-allowed`} {...props}>
        {children}
      </select>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"
        className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 dark:text-zinc-500">
        <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
      </svg>
    </div>
  )
})

export default Select
