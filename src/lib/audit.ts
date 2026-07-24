import { supabaseBrowser } from '$lib/supabase-browser';

export type AuditLog = {
	id: number;
	table_name: string;
	record_id: string | null;
	operation: 'INSERT' | 'UPDATE' | 'DELETE';
	actor_user_id: string | null;
	actor_name: string | null;
	target_label: string | null;
	old_data: Record<string, unknown> | null;
	new_data: Record<string, unknown> | null;
	changed_fields: string[] | null;
	changed_at: string;
};

// 테이블 → 한글 이름
export const TABLE_LABELS: Record<string, string> = {
	education_reports: '교육부서 보고서',
	education_report_editors: '보고서 담당자',
	attendance_records: '출석 체크',
	member_notes: '특이사항',
	group_session_notes: '소그룹 기타의견',
	small_group_members: '소그룹 명단',
	attendance_managers: '교역자 지정',
	attendance_stat_viewers: '통계 열람자',
	attendance_sessions: '출석 주차',
	small_groups: '소그룹',
	communities: '공동체'
};

// 기능 그룹 필터
export const FEATURES: { key: string; label: string; tables: string[] }[] = [
	{ key: 'all', label: '전체', tables: [] },
	{ key: 'education', label: '교육부서', tables: ['education_reports', 'education_report_editors'] },
	{
		key: 'attendance',
		label: '출석부',
		tables: [
			'attendance_records',
			'member_notes',
			'group_session_notes',
			'small_group_members',
			'attendance_managers',
			'attendance_stat_viewers',
			'attendance_sessions',
			'small_groups',
			'communities'
		]
	}
];

// 컬럼 → 한글 라벨
export const FIELD_LABELS: Record<string, string> = {
	enrolled: '재적',
	attend: '출석',
	attend_online: '출석(on)',
	teacher_enrolled: '교사재적',
	teacher_attend: '교사출석',
	attendance_note: '비고/새가족',
	this_week: '이번 주',
	next_week: '다음 주',
	event_note: '비고/건의',
	note: '메모',
	role: '역할',
	active: '활성',
	present: '출석',
	sort_order: '순서',
	name: '이름',
	department: '부서',
	report_date: '날짜',
	session_date: '날짜',
	label: '라벨',
	member_id: '구성원',
	small_group_id: '소그룹',
	session_id: '주차',
	user_id: '사용자',
	community_id: '공동체'
};

export function opLabel(op: string): string {
	return op === 'INSERT' ? '추가' : op === 'DELETE' ? '삭제' : '수정';
}
export function opClass(op: string): string {
	return op === 'INSERT'
		? 'bg-green-100 text-green-700'
		: op === 'DELETE'
			? 'bg-red-100 text-red-600'
			: 'bg-blue-100 text-blue-700';
}

export function fieldLabel(field: string): string {
	return FIELD_LABELS[field] ?? field;
}

/** 값 표시용 포맷 (감사 diff). */
export function fmtVal(v: unknown): string {
	if (v === null || v === undefined || v === '') return '(없음)';
	if (typeof v === 'boolean') return v ? '예' : '아니오';
	if (v === 'leader') return '리더';
	if (v === 'member') return '멤버';
	let s = String(v);
	s = s.replace(/\s+/g, ' ').trim();
	return s.length > 60 ? s.slice(0, 60) + '…' : s;
}

/** 현재 로그인 사용자가 관리자(level>=100)인지. */
export async function loadIsAdmin(): Promise<{ hasSession: boolean; isAdmin: boolean }> {
	const {
		data: { session }
	} = await supabaseBrowser.auth.getSession();
	if (!session) return { hasSession: false, isAdmin: false };
	const { data: me } = await supabaseBrowser
		.from('custom_users')
		.select('roles(level)')
		.eq('auth_id', session.user.id)
		.single();
	const level = (me?.roles as unknown as { level: number } | null)?.level ?? 0;
	return { hasSession: true, isAdmin: level >= 100 };
}
