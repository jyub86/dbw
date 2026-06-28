import { supabaseBrowser } from '$lib/supabase-browser';

/**
 * 로그인 사용자의 명단(custom_users) 행에 이름·전화가 모두 채워졌는지 여부.
 * 행이 없거나 둘 중 하나라도 비어 있으면 false (프로필 입력 필요).
 */
export async function isProfileComplete(authId: string): Promise<boolean> {
	const { data: me } = await supabaseBrowser
		.from('custom_users')
		.select('name, phone')
		.eq('auth_id', authId)
		.maybeSingle();
	return !!(me && me.name?.trim() && me.phone?.trim());
}
