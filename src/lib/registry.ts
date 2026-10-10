import { supabaseBrowser } from '$lib/supabase-browser';

/**
 * 교적(재적) 화면 공용.
 *
 * 교적 데이터는 API 로 바로 읽을 수 없다(registry 스키마 비노출). 모든 조회·수정은 public.registry_* 함수를 거치고,
 * 함수가 권한·2단계 인증을 확인한 뒤 접속기록을 남긴다. 설계: docs/church-admin/02-registry-design.md
 */

export type RegistryMe = {
	is_staff: boolean;
	is_admin: boolean;
	can_edit: boolean;
	can_export: boolean;
	can_pastoral: boolean;
	mfa_required: boolean;
	aal: 'aal1' | 'aal2';
	idle_minutes: number;
};

/** 내 교적 권한. 로그인 안 했으면 hasSession=false */
export async function loadRegistryMe(): Promise<{ hasSession: boolean; me: RegistryMe | null }> {
	const {
		data: { session }
	} = await supabaseBrowser.auth.getSession();
	if (!session) return { hasSession: false, me: null };
	const { data, error } = await supabaseBrowser.rpc('registry_me');
	if (error || !data) return { hasSession: true, me: null };
	return { hasSession: true, me: data as RegistryMe };
}

type RpcError = { message?: string; hint?: string | null; code?: string } | null;

/** DB 함수가 2단계 인증을 요구했는지 (registry.require_mfa 가 hint 로 알려 준다) */
export const needsMfa = (e: RpcError) => e?.hint === 'mfa_required';

/** 화면에 보여 줄 오류 문구. DB 함수는 한국어 문구로 예외를 던진다. */
export function errText(e: RpcError, fallback = '처리하지 못했습니다.'): string {
	if (!e) return fallback;
	const m = e.message ?? '';
	if (/permission denied/i.test(m)) return '권한이 없습니다.';
	if (/check constraint|violates|invalid input/i.test(m)) return fallback;
	return /[가-힣]/.test(m) ? m : fallback;
}

/** 교적 함수 호출. 실패하면 화면에 보여 줄 문구를 돌려준다. */
export async function call<T = unknown>(
	fn: string,
	args: Record<string, unknown>,
	fallback?: string
): Promise<{ ok: true; data: T } | { ok: false; error: string }> {
	const { data, error } = await supabaseBrowser.rpc(fn, args);
	if (error) return { ok: false, error: needsMfa(error) ? '2단계 인증이 풀렸습니다. 새로고침해 주세요.' : errText(error, fallback) };
	return { ok: true, data: data as T };
}

// ─── 2단계 인증 (Supabase Auth TOTP) ───

export type MfaStatus = { level: 'aal1' | 'aal2' | null; factorId: string | null };

export async function mfaStatus(): Promise<MfaStatus> {
	const { data: aal } = await supabaseBrowser.auth.mfa.getAuthenticatorAssuranceLevel();
	const { data: factors } = await supabaseBrowser.auth.mfa.listFactors();
	return {
		level: (aal?.currentLevel as 'aal1' | 'aal2' | undefined) ?? null,
		// listFactors().totp 에는 확인을 마친 인증 앱만 들어 있다
		factorId: factors?.totp?.[0]?.id ?? null
	};
}

/** 인증 앱 등록을 시작한다. 등록을 마치지 않고 떠난 흔적이 있으면 먼저 지운다. */
export async function mfaEnroll(): Promise<{ factorId: string; qr: string; secret: string } | { error: string }> {
	const { data: factors } = await supabaseBrowser.auth.mfa.listFactors();
	for (const f of factors?.all ?? []) {
		if (f.status === 'unverified') await supabaseBrowser.auth.mfa.unenroll({ factorId: f.id });
	}
	const { data, error } = await supabaseBrowser.auth.mfa.enroll({
		factorType: 'totp',
		friendlyName: `교적 ${new Date().toISOString().slice(0, 10)}`
	});
	if (error || !data) return { error: error?.message ?? '인증 앱 등록을 시작하지 못했습니다.' };
	// 버전에 따라 SVG 원문 또는 data URL 로 온다
	const q = data.totp.qr_code;
	const qr = q.startsWith('data:') ? q : `data:image/svg+xml;utf-8,${encodeURIComponent(q)}`;
	return { factorId: data.id, qr, secret: data.totp.secret };
}

/** 인증 앱의 6자리 코드로 확인. 성공하면 세션이 aal2 로 바뀐다. */
export async function mfaVerify(factorId: string, code: string): Promise<string | null> {
	const { error } = await supabaseBrowser.auth.mfa.challengeAndVerify({ factorId, code: code.trim() });
	return error ? '코드가 맞지 않습니다. 인증 앱의 최신 6자리를 넣어 주세요.' : null;
}

// ─── 라벨 ───

export const STATUS_LABEL: Record<string, string> = {
	active: '재적',
	hold: '보류',
	transferred: '전출',
	deceased: '별세',
	removed: '제적'
};
export const STATUS_STYLE: Record<string, string> = {
	active: 'bg-primary-50 text-primary-800',
	hold: 'bg-amber-50 text-amber-700',
	transferred: 'bg-gray-100 text-gray-500',
	deceased: 'bg-gray-100 text-gray-500',
	removed: 'bg-red-50 text-red-600'
};

/** 재적 이벤트 종류 → 화면 이름 (결과 상태는 DB 의 registry.status_of_kind 가 정한다) */
export const STATUS_KINDS = [
	{ kind: 'register', label: '등록' },
	{ kind: 'transfer_in', label: '전입' },
	{ kind: 'restore', label: '복적' },
	{ kind: 'hold', label: '보류' },
	{ kind: 'transfer_out', label: '전출' },
	{ kind: 'deceased', label: '별세' },
	{ kind: 'removed', label: '제적' }
] as const;
export const STATUS_KIND_LABEL: Record<string, string> = Object.fromEntries(STATUS_KINDS.map((k) => [k.kind, k.label]));

export const FAITH_LABEL: Record<string, string> = {
	baptized: '세례교인',
	infant_baptized: '유아세례교인',
	catechumen: '학습교인',
	seeker: '원입교인',
	unknown: '미확인'
};
export const FAITH_KINDS = [
	{ kind: 'catechumen', label: '학습' },
	{ kind: 'baptism', label: '세례' },
	{ kind: 'infant_baptism', label: '유아세례' },
	{ kind: 'confirmation', label: '입교' }
] as const;
export const FAITH_KIND_LABEL: Record<string, string> = Object.fromEntries(FAITH_KINDS.map((k) => [k.kind, k.label]));

export const STANDING_LABEL: Record<string, string> = {
	serving: '시무',
	retired: '은퇴',
	emeritus: '원로',
	honorary: '명예',
	cooperating: '협동',
	resigned: '사임'
};

export const CONSENT_LABEL: Record<string, string> = {
	registry: '교적 등록',
	sensitive: '민감정보',
	directory: '요람 공개',
	guardian: '보호자 동의(14세 미만)'
};
export const METHOD_LABEL: Record<string, string> = { paper: '서면', app: '앱', verbal: '구두' };

// ─── 함수가 돌려주는 모양 ───

/** registry_search 한 행 */
export type PersonRow = {
	person_id: string;
	name: string | null;
	name_note: string | null;
	gender: string | null;
	birth_date: string | null;
	phone: string | null;
	office: string | null;
	status: string;
	faith: string;
	community_id: number | null;
	community_name: string | null;
	group_id: number | null;
	group_name: string | null;
	has_account: boolean;
	registered_on: string | null;
	total: number;
};

/** registry_card 결과 */
export type Card = {
	person: {
		person_id: string;
		name: string | null;
		phone: string | null;
		gender: string | null;
		birth_date: string | null;
		office: string | null;
		photo: string | null;
		email: string | null;
		member: boolean;
		has_account: boolean;
		reg_no: string | null;
		name_note: string | null;
		birth_lunar: boolean;
		address_zip: string | null;
		address1: string | null;
		address2: string | null;
		occupation: string | null;
		workplace: string | null;
		marital_status: string | null;
		wedding_date: string | null;
		previous_church: string | null;
		guide_person_id: string | null;
		guide_name: string | null;
		sms_opt_out: boolean;
		faith_checked_on: string | null;
		note: string | null;
		created_at: string;
		updated_at: string;
	};
	summary: {
		status: string;
		faith: string;
		office: string | null;
		standing: string | null;
		registered_on: string | null;
		community_name: string | null;
		group_name: string | null;
	};
	guide: string | null;
	groups: { group_id: number; group_name: string; community_name: string; role: string; active: boolean; joined_at: string }[];
	household: {
		id: number;
		household_no: string | null;
		address_zip: string | null;
		address1: string | null;
		address2: string | null;
		home_phone: string | null;
		note: string | null;
		members: {
			id: number;
			person_id: string | null;
			name: string | null;
			relation: string;
			office: string | null;
			birth_year: number | null;
			note: string | null;
		}[];
	} | null;
	status_events: { id: number; kind: string; event_date: string | null; reason: string | null; church_name: string | null }[];
	faith_events: { id: number; kind: string; event_date: string | null; church_name: string | null; officiant: string | null; note: string | null }[];
	office_terms: { id: number; office: string; label: string | null; standing: string; started_on: string | null; ended_on: string | null; note: string | null }[];
	notes: { id: number; body: string; created_at: string; author: string | null }[];
	consents: {
		id: number;
		kind: string;
		notice_version: string | null;
		granted_on: string;
		method: string;
		guardian_name: string | null;
		revoked_on: string | null;
		note: string | null;
	}[];
	history: {
		at: string;
		table: string;
		op: string;
		actor: string | null;
		fields: string[] | null;
		old: Record<string, unknown> | null;
		new: Record<string, unknown> | null;
	}[];
};

export type Code = { category: string; code: string; label: string; title: string | null; sort_order: number };

export async function loadCodes(): Promise<Code[]> {
	const { data } = await supabaseBrowser.rpc('registry_codes');
	return (data ?? []) as Code[];
}
export const codesOf = (codes: Code[], category: string) => codes.filter((c) => c.category === category);
export const codeLabel = (codes: Code[], category: string, code: string | null | undefined) =>
	codes.find((c) => c.category === category && c.code === code)?.label ?? code ?? '';

/** 만 나이 */
export function age(birth: string | null | undefined): number | null {
	if (!birth) return null;
	const b = new Date(birth);
	const now = new Date();
	let a = now.getFullYear() - b.getFullYear();
	const m = now.getMonth() - b.getMonth();
	if (m < 0 || (m === 0 && now.getDate() < b.getDate())) a--;
	return a;
}

/** 오늘 날짜 (기기 시간대 기준, YYYY-MM-DD). toISOString 은 UTC 라 한국 오전에 하루 전 날짜가 된다 */
export const today = () => new Date().toLocaleDateString('sv-SE');

export const fmtDateTime = (iso: string) =>
	new Date(iso).toLocaleString('ko-KR', { dateStyle: 'short', timeStyle: 'short' });
