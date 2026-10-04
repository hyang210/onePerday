import type { Metadata } from 'next'
import './globals.css'
import Link from 'next/link'
import Image from 'next/image'
import AuthGate from '../components/AuthGate'
import LogoutButton from '../components/LogoutButton'

export const metadata: Metadata = {
  title: '관리자 페이지',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body>
        <nav style={{
          backgroundColor: '#2d8a5e',
          padding: '0 2rem',
          display: 'flex',
          alignItems: 'center',
          gap: '2rem',
          height: '60px',
          boxShadow: '0 2px 8px rgba(0,0,0,0.1)'
        }}>
          <Link href="/">
            <Image src="/logo.png" alt="logo" width={48} height={48} style={{ borderRadius: '6px', cursor: 'pointer' }} />
          </Link>          
          <Link href="/users" style={{
            color: 'rgba(255,255,255,0.85)',
            textDecoration: 'none',
            fontSize: '15px',
            fontWeight: 500,
          }}>유저 관리</Link>
          <Link href="/supplements" style={{
            color: 'rgba(255,255,255,0.85)',
            textDecoration: 'none',
            fontSize: '15px',
            fontWeight: 500,
          }}>영양제 관리</Link>
          <LogoutButton />
        </nav>
        <main style={{ padding: '2rem', maxWidth: '1200px', margin: '0 auto' }}>
          <AuthGate>{children}</AuthGate>
        </main>
      </body>
    </html>
  )
}