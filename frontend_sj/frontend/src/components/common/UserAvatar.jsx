import { useState } from 'react'
import { resolveUploadUrl } from '../../services/api'

// The user's profile picture, or their initials on a green circle when there is none (or it
// fails to load). Size and text size come from the caller, e.g. "w-8 h-8 text-xs".
export default function UserAvatar({ user, className = 'w-8 h-8 text-xs' }) {
  const [failedUrl, setFailedUrl] = useState(null)
  const name = user?.fullName || user?.username || 'User'
  const initials = name.split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase()
  const url = user?.avatarUrl

  if (url && failedUrl !== url) {
    return (
      <img
        src={resolveUploadUrl(url)}
        alt={`Profile picture of ${name}`}
        onError={() => setFailedUrl(url)}
        className={`${className} rounded-full object-cover flex-shrink-0 bg-slate-100 dark:bg-zinc-800`}
      />
    )
  }
  return (
    <div className={`${className} rounded-full bg-brand-500 text-white font-bold flex items-center justify-center select-none flex-shrink-0`}
      aria-hidden="true">
      {initials}
    </div>
  )
}
