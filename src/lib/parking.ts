import { supabaseBrowser } from '$lib/supabase-browser';

export type ParkingAccess = {
	userId: string;
	isAdmin: boolean; // roles.level >= 100
	isManager: boolean; // parking_managers 등록 (주차 담당자)
	canManage: boolean; // 차량 조회·현황 열람 가능
};

/** 현재 로그인 사용자의 주차 권한을 로드. session 없으면 access=null. */
export async function loadParkingAccess(): Promise<{
	hasSession: boolean;
	access: ParkingAccess | null;
}> {
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

	// parking_managers RLS: 본인 행은 조회 가능 → count 로 판별
	const { count } = await supabaseBrowser
		.from('parking_managers')
		.select('user_id', { count: 'exact', head: true })
		.eq('user_id', me.id);
	const isManager = (count ?? 0) > 0;

	return {
		hasSession: true,
		access: { userId: me.id, isAdmin, isManager, canManage: isAdmin || isManager }
	};
}

/** 검색·중복판정용 정규화. DB 의 normalize_plate() 와 같은 규칙이어야 한다. */
export const normalizePlate = (s: string) =>
	(s ?? '').replace(/[^0-9A-Za-z가-힣]/g, '').toUpperCase();

/**
 * 한국 번호판 형태인지 대략 확인한다. (예: 12가3456, 123가4567, 서울12가3456)
 * 임시번호판·외교차량 등 예외가 있어 **차단하지 않고 안내만** 하는 용도다.
 */
export function looksLikePlate(s: string): boolean {
	return /^(?:[가-힣]{2})?\d{2,3}[가-힣]\d{4}$/.test(normalizePlate(s));
}
