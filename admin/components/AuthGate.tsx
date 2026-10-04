'use client'
import { useEffect, useState } from 'react'
import { usePathname, useRouter } from 'next/navigation'
import { supabase } from '../lib/supabase'

// 로그인하지 않은 상태로 관리자 페이지에 들어오면 /login으로 보냅니다.
// (실제 권한 검사는 백엔드 AdminGuard가 합니다.)
export default function AuthGate({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const router = useRouter()
  const isLoginPage = pathname === '/login'
  const [ready, setReady] = useState(false)

  useEffect(() => {
    if (isLoginPage) return
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) setReady(true)
      else router.replace('/login')
    })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) router.replace('/login')
    })
    return () => listener.subscription.unsubscribe()
  }, [isLoginPage, router])

  if (isLoginPage) return <>{children}</>
  return ready ? <>{children}</> : null
}
