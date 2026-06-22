import { supabaseBrowser } from '$lib/supabase-browser';

export type Access = {
    userId: string;
    level: number;
    isAdmin: boolean; // roles.level >= 100
    isManager: boolean; // attendance_managers 등록 (지정 교역자)
    canManage: boolean; // 명단/통계 관리 가능 (admin 또는 manager)
};

/** 현재 로그인 사용자의 출석부 권한을 로드. session 없으면 access=null. */
export async function loadAccess(): Promise<{ hasSession: boolean; access: Access | null }> {
    const {
        data: { session }
    } = await supabaseBrowser.auth.getSession();
    if (!session) return { hasSession: false, access: null };

    const { data: me } = await supabaseBrowser
        .from('custom_users')
        .select('id, roles(level)')
        .eq('auth_id', session.user.id)
        .single();
    if (!me) return { hasSession: true, access: null };

    const level = (me.roles as unknown as { level: number } | null)?.level ?? 0;
    const isAdmin = level >= 100;

    // attendance_managers RLS: 본인이 매니저/관리자일 때만 조회됨 → count로 판별
    const { count } = await supabaseBrowser
        .from('attendance_managers')
        .select('user_id', { count: 'exact', head: true })
        .eq('user_id', me.id);
    const isManager = (count ?? 0) > 0;

    return {
        hasSession: true,
        access: { userId: me.id, level, isAdmin, isManager, canManage: isAdmin || isManager }
    };
}

/**
 * PostgREST는 요청당 최대 1000행만 반환하므로, 1000행 단위로 끝까지 가져온다.
 * build(from,to)는 .range(from,to)가 적용된 쿼리를 반환해야 한다.
 */
export async function fetchAll<T>(
    build: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>
): Promise<T[]> {
    const PAGE = 1000;
    let from = 0;
    const out: T[] = [];
    // eslint-disable-next-line no-constant-condition
    while (true) {
        const { data, error } = await build(from, from + PAGE - 1);
        if (error || !data || data.length === 0) break;
        out.push(...data);
        if (data.length < PAGE) break;
        from += PAGE;
    }
    return out;
}

export function fmtDate(iso: string) {
    const [, m, d] = iso.split('-');
    return `${Number(m)}월 ${Number(d)}일`;
}

export function pct(r: number) {
    return Math.round(r * 100);
}

// 한국시간(Asia/Seoul) 기준 오늘 날짜 'YYYY-MM-DD'. (UTC 변환으로 인한 날짜 밀림 방지)
export const todayISO = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Seoul' });
