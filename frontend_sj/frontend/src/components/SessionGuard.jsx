import { useEffect, useRef } from 'react'
import { useDispatch, useSelector } from 'react-redux'
import { useNavigate } from 'react-router-dom'
import { getMe } from '../services/authService'
import { setCredentials, logout } from '../store/slices/authSlice'
import { useToast } from '../context/ToastContext'

// The JWT is a browser-wide cookie, but the signed-in user shown in the UI is kept per tab
// (sessionStorage). Signing in as someone else in another tab silently swaps the cookie, so
// this tab would keep showing e.g. a staff view while every request runs as the other
// account (an admin sees every office). Re-checks who the server says is signed in when the
// tab loads and whenever it regains focus, and switches the UI to match. It also picks up
// an office an admin assigned since sign-in.
function SessionGuard() {
  const dispatch = useDispatch()
  const navigate = useNavigate()
  const toast    = useToast()
  const user     = useSelector((s) => s.auth.user)
  const userRef  = useRef(user)
  userRef.current = user

  useEffect(() => {
    let checking = false
    const check = async () => {
      if (checking || document.visibilityState === 'hidden') return
      checking = true
      try {
        const { data: me } = await getMe()
        const shown = userRef.current
        if (!me) return
        if (shown?.username !== me.username || shown?.role !== me.role) {
          dispatch(setCredentials({ user: me }))
          toast.show(`You're signed in as ${me.fullName || me.username} (signed in from another tab). Switched to that account.`, 'warning')
          navigate('/dashboard', { replace: true })
        } else if (shown?.officeId !== me.officeId || shown?.officeName !== me.officeName) {
          dispatch(setCredentials({ user: { ...shown, officeId: me.officeId, officeName: me.officeName } }))
        }
      } catch (err) {
        if (err.response?.status === 401) {
          dispatch(logout())
          navigate('/login', { replace: true })
        }
      } finally {
        checking = false
      }
    }
    check()
    window.addEventListener('focus', check)
    document.addEventListener('visibilitychange', check)
    return () => {
      window.removeEventListener('focus', check)
      document.removeEventListener('visibilitychange', check)
    }
  }, [dispatch, navigate, toast])

  return null
}

export default SessionGuard
