import { createClient } from '@supabase/supabase-js'

// 앱과 같은 Supabase 프로젝트의 URL / publishable(anon) 키
export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL ?? '',
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '',
)
