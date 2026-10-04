import { supabase } from './supabase';

const BASE_URL = process.env.NEXT_PUBLIC_API_URL;

// 로그인 토큰을 붙여 백엔드를 호출합니다. 토큰이 없거나 관리자가 아니면 로그인 화면으로 보냅니다.
async function authFetch(url: string, init: RequestInit = {}) {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  const res = await fetch(url, {
    ...init,
    headers: {
      ...init.headers,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
  if (res.status === 401 || res.status === 403) {
    await supabase.auth.signOut();
    window.location.href = '/login';
    throw new Error('관리자 로그인이 필요합니다.');
  }
  return res;
}

export const api = {
  // 유저
  getUsers: (search?: string) =>
    authFetch(`${BASE_URL}/admin/users?search=${search ?? ''}`).then(r => r.json()),

  deleteUser: (id: string) =>
    authFetch(`${BASE_URL}/admin/users/${id}`, { method: 'DELETE' }).then(r => r.json()),

  // 영양제
  getSupplements: (keyword?: string, page?: number) =>
      authFetch(`${BASE_URL}/admin/supplements?keyword=${keyword ?? ''}&page=${page ?? 1}`).then(r => r.json()),

  addSupplement: (data: any) =>
    authFetch(`${BASE_URL}/admin/supplements`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    }).then(r => r.json()),

  deleteSupplement: (id: string) =>
    authFetch(`${BASE_URL}/admin/supplements/${id}`, { method: 'DELETE' }).then(r => r.json()),

  getDashboard: () =>
    authFetch(`${BASE_URL}/admin/dashboard`).then(r => r.json()),

  updateUser: (id: string, data: any) =>
    authFetch(`${BASE_URL}/admin/users/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    }).then(r => r.json()),

  updateSupplement: (id: string, data: any) =>
    authFetch(`${BASE_URL}/admin/supplements/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    }).then(r => r.json()),  
};