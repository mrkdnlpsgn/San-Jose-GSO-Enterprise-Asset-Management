// Slim identity bar shared by the login screen and the authenticated app shell —
// the one piece of chrome that names the Republic/LGU outright, the way live
// .gov.ph portals lead with a masthead rather than leaving it to the seal alone.
function GovMasthead() {
  return (
    <div className="h-7 flex-shrink-0 bg-gov-800 dark:bg-gov-900 flex items-center justify-center px-4">
      <p className="text-2xs font-medium tracking-wide text-gov-100 text-center truncate">
        Republic of the Philippines
        <span className="mx-2 text-gov-400">·</span>
        Municipality of San Jose, Batangas
      </p>
    </div>
  )
}

export default GovMasthead
