'use client'
import { usePathname } from 'next/navigation'
import { supabase } from '../lib/supabase'

export default function LogoutButton() {
  const pathname = usePathname()
  if (pathname === '/login') return null

  return (
    <button
      type="button"
      onClick={() => supabase.auth.signOut()}
      style={{
        marginLeft: 'auto',
        background: 'transparent',
        border: '1px solid rgba(255,255,255,0.6)',
        borderRadius: '6px',
        color: 'white',
        padding: '6px 12px',
        fontSize: '14px',
        cursor: 'pointer',
      }}
    >
      로그아웃
    </button>
  )
}
