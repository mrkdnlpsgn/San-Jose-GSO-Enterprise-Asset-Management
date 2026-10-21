import { useEffect, useState } from 'react'
import api from '../../services/api'

// The newest Android app release, from the same endpoint the mobile app checks for updates
// (GET /api/app/version, public). Asked once per page load and shared by every link. Nothing
// shows until the server has a download link set (MOBILE_DOWNLOAD_URL on Render).
let releaseRequest = null
function fetchRelease() {
  if (!releaseRequest) {
    releaseRequest = api.get('/app/version')
      .then((res) => (res.data?.downloadUrl ? res.data : null))
      .catch(() => { releaseRequest = null; return null }) // server asleep — try again next mount
  }
  return releaseRequest
}

function useMobileRelease() {
  const [release, setRelease] = useState(null)
  useEffect(() => {
    let alive = true
    fetchRelease().then((r) => { if (alive) setRelease(r) })
    return () => { alive = false }
  }, [])
  return release
}

const PhoneIcon = ({ className }) => (
  <svg xmlns="http://www.w3.org/2000/svg" className={className} viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
    <path fillRule="evenodd" d="M7 2a2 2 0 00-2 2v12a2 2 0 002 2h6a2 2 0 002-2V4a2 2 0 00-2-2H7zm3 14a1 1 0 100-2 1 1 0 000 2z" clipRule="evenodd" />
  </svg>
)

// variant "login": a full-width outlined button under the sign-in form.
// variant "sidebar": a small text link in the sidebar footer.
function DownloadAppLink({ variant = 'login', className = '' }) {
  const release = useMobileRelease()
  if (!release) return null
  const version = release.latestVersion ? `v${release.latestVersion}` : null

  if (variant === 'sidebar') {
    return (
      <a
        href={release.downloadUrl}
        target="_blank"
        rel="noopener noreferrer"
        className={`text-2xs text-slate-400 dark:text-zinc-600 hover:text-brand-500 dark:hover:text-brand-400 py-1.5 flex items-center gap-1 whitespace-nowrap transition-colors duration-150 ${className}`}
      >
        <PhoneIcon className="h-3 w-3 flex-shrink-0" />
        Download the Android app{version && ` (${version})`}
      </a>
    )
  }

  return (
    <a
      href={release.downloadUrl}
      target="_blank"
      rel="noopener noreferrer"
      className={`flex items-center gap-3 rounded-lg border border-slate-200 dark:border-zinc-700 px-4 py-3 hover:border-brand-500/50 hover:bg-brand-500/5 transition-colors duration-150 focus:outline-none focus:ring-2 focus:ring-brand-500 ${className}`}
    >
      <span className="flex-shrink-0 w-9 h-9 rounded-md bg-brand-500/10 flex items-center justify-center">
        <PhoneIcon className="h-5 w-5 text-brand-700 dark:text-brand-400" />
      </span>
      <span className="min-w-0 text-left">
        <span className="block text-sm font-semibold text-slate-800 dark:text-zinc-100">Download the mobile app</span>
        <span className="block text-xs text-slate-500 dark:text-zinc-400">
          For Android phones{version && ` · ${version}`} · APK file
        </span>
      </span>
      <svg xmlns="http://www.w3.org/2000/svg" className="ml-auto h-5 w-5 flex-shrink-0 text-slate-400 dark:text-zinc-500" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
      </svg>
    </a>
  )
}

export default DownloadAppLink
