This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## 환경 변수

`admin/.env.local`에 아래 값을 설정합니다. (`NEXT_PUBLIC_` 값은 빌드 시점에 고정되므로 바꾸면 다시 빌드해야 합니다.)

```env
NEXT_PUBLIC_API_URL="http://localhost:3000"
NEXT_PUBLIC_SUPABASE_URL="https://your-project.supabase.co"
NEXT_PUBLIC_SUPABASE_ANON_KEY="sb_publishable_..."
```

## 관리자 로그인

Supabase 이메일/비밀번호 로그인을 사용합니다.

1. Supabase 대시보드 → Authentication → Users → **Add user**로 관리자 계정을 만듭니다. (Email 로그인 provider가 켜져 있어야 합니다.)
2. 백엔드 `.env`의 `ADMIN_EMAILS`에 그 이메일을 추가합니다.
3. 관리자 웹 `/login`에서 로그인합니다. 관리자가 아닌 계정은 로그인되지 않습니다.

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
