import { useEffect, useState } from 'react'
import api from '../services/api'

// The newest Android app release, from the same endpoint the mobile app checks for updates
// (GET /api/app/version, public): { latestVersion, downloadUrl, ... }, or null until the server
// has a download link set (MOBILE_DOWNLOAD_URL on Render). Asked once per page load.
let releaseRequest = null
function fetchRelease() {
  if (!releaseRequest) {
    releaseRequest = api.get('/app/version')
      .then((res) => (res.data?.downloadUrl ? res.data : null))
      .catch(() => { releaseRequest = null; return null }) // server asleep - try again next mount
  }
  return releaseRequest
}

export function useMobileRelease() {
  const [release, setRelease] = useState(null)
  useEffect(() => {
    let alive = true
    fetchRelease().then((r) => { if (alive) setRelease(r) })
    return () => { alive = false }
  }, [])
  return release
}
