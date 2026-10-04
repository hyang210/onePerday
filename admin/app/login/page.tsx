'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '../../lib/supabase'

export default function LoginPage() {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const { data, error: signInError } = await supabase.auth.signInWithPassword({ email, password })
      if (signInError || !data.session) {
        setError('이메일 또는 비밀번호가 올바르지 않습니다.')
        return
      }

      // 백엔드에서 관리자(ADMIN_EMAILS) 계정인지 확인
      const res = await fetch(`${process.env.NEXT_PUBLIC_API_URL}/auth/me`, {
        headers: { Authorization: `Bearer ${data.session.access_token}` },
      })
      const me = res.ok ? await res.json() : null
      if (!me?.isAdmin) {
        await supabase.auth.signOut()
        setError('관리자 권한이 없는 계정입니다.')
        return
      }

      router.replace('/')
    } catch {
      setError('로그인 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.')
    } finally {
      setLoading(false)
    }
  }

  const inputStyle = {
    width: '100%',
    padding: '10px 12px',
    border: '1px solid #ccc',
    borderRadius: '6px',
    fontSize: '14px',
    boxSizing: 'border-box' as const,
  }

  return (
    <div style={{ maxWidth: '360px', margin: '4rem auto' }}>
      <h1 style={{ fontSize: '22px', fontWeight: 700, color: '#2d8a5e', marginBottom: '1.5rem' }}>
        관리자 로그인
      </h1>
      <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        <input
          type="email"
          placeholder="이메일"
          value={email}
          onChange={e => setEmail(e.target.value)}
          required
          autoComplete="username"
          style={inputStyle}
        />
        <input
          type="password"
          placeholder="비밀번호"
          value={password}
          onChange={e => setPassword(e.target.value)}
          required
          autoComplete="current-password"
          style={inputStyle}
        />
        {error && <p style={{ color: '#d32f2f', fontSize: '13px', margin: 0 }}>{error}</p>}
        <button
          type="submit"
          disabled={loading}
          style={{
            padding: '10px',
            backgroundColor: '#2d8a5e',
            color: 'white',
            border: 'none',
            borderRadius: '6px',
            fontSize: '15px',
            fontWeight: 600,
            cursor: loading ? 'default' : 'pointer',
            opacity: loading ? 0.7 : 1,
          }}
        >
          {loading ? '로그인 중...' : '로그인'}
        </button>
      </form>
    </div>
  )
}
