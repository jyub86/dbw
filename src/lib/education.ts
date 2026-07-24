import { supabaseBrowser } from '$lib/supabase-browser';

// 교육부서(고정 5개, 표시 순서). DB에는 department 텍스트로 저장.
export const DEPARTMENTS = ['영아부', '유치부', '유초등부', '중고등부', '청년부'] as const;
export type Department = (typeof DEPARTMENTS)[number];

export type EducationRow = {
	id?: string;
	report_date: string;
	department: string;
	enrolled: number | null; // 재적
	attend: number | null; // 출석
	attend_online: number | null; // 출석(on)
	teacher_enrolled: number | null; // 교사재적
	teacher_attend: number | null; // 교사출석
	attendance_note: string | null; // 비고 및 새가족
	this_week: string | null; // 이번 주
	next_week: string | null; // 다음 주
	event_note: string | null; // 비고 및 건의사항
	updated_at?: string;
};

export type EducationAccess = {
	userId: string;
	isAdmin: boolean; // roles.level >= 100
	isEditor: boolean; // education_report_editors 등록
	canAccess: boolean; // 열람·수정 가능 (admin 또는 editor)
};

/** 현재 로그인 사용자의 교육부서 보고서 권한을 로드. session 없으면 access=null. */
export async function loadEducationAccess(): Promise<{
	hasSession: boolean;
	access: EducationAccess | null;
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

	// education_report_editors RLS: 본인 행은 조회 가능 → count로 판별
	const { count } = await supabaseBrowser
		.from('education_report_editors')
		.select('user_id', { count: 'exact', head: true })
		.eq('user_id', me.id);
	const isEditor = (count ?? 0) > 0;

	return {
		hasSession: true,
		access: { userId: me.id, isAdmin, isEditor, canAccess: isAdmin || isEditor }
	};
}

/** 빈 부서 행(신규 보고서 작성용). */
export function blankRow(date: string, department: string): EducationRow {
	return {
		report_date: date,
		department,
		enrolled: null,
		attend: null,
		attend_online: null,
		teacher_enrolled: null,
		teacher_attend: null,
		attendance_note: null,
		this_week: null,
		next_week: null,
		event_note: null
	};
}

/** 부서 표시 순서 인덱스(정렬용). */
export function deptOrder(dept: string): number {
	const i = (DEPARTMENTS as readonly string[]).indexOf(dept);
	return i === -1 ? 99 : i;
}

/** 'YYYY-MM-DD' → '2026년 7월 19일 (일)' */
export function fmtFullDate(iso: string): string {
	const [y, m, d] = iso.split('-').map(Number);
	const wd = ['일', '월', '화', '수', '목', '금', '토'][new Date(y, m - 1, d).getDay()];
	return `${y}년 ${m}월 ${d}일 (${wd})`;
}

/** 'YYYY-MM-DD' → '7.19' (목록 카드용) */
export function fmtShort(iso: string): string {
	const [, m, d] = iso.split('-').map(Number);
	return `${m}.${d}`;
}

// 한국시간(Asia/Seoul) 기준 오늘 날짜 'YYYY-MM-DD'.
export const todayISO = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Seoul' });
