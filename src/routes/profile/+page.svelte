<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabaseBrowser } from '$lib/supabase-browser';

	type Embed<T> = T | T[] | null;
	type Me = {
		id: string;
		email: string | null;
		name: string | null;
		phone: string | null;
		profile_picture: string | null;
		gender: string | null;
		birth_date: string | null;
		office: string;
		member: boolean;
		active: boolean;
		created_at: string;
		is_info_public: boolean;
		privacy_consented_at: string | null;
		roles: Embed<{ name: string | null; level: number }>;
	};
	const one = <T,>(v: Embed<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : (v ?? null));
	const fmtDay = (iso: string | null) => (iso ? iso.slice(0, 10).replaceAll('-', '.') : '-');

	let loading = $state(true);
	let saving = $state(false);
	let notFound = $state(false);
	let msg = $state('');
	let errorMsg = $state('');

	let me = $state<Me | null>(null);

	// 편집 가능한 값만 따로 들고 있는다 (직분·교인 여부·권한은 교회가 관리한다).
	let name = $state('');
	let phone = $state('');
	let birthDate = $state('');
	let gender = $state('');
	let infoPublic = $state(false);

	const roleName = $derived(one(me?.roles ?? null)?.name ?? '사용자');
	const phoneDigits = $derived(phone.replace(/\D/g, ''));
	const dirty = $derived(
		!!me &&
			(name.trim() !== (me.name ?? '').trim() ||
				phoneDigits !== (me.phone ?? '').replace(/\D/g, '') ||
				birthDate !== (me.birth_date ?? '') ||
				gender !== (me.gender ?? '') ||
				infoPublic !== me.is_info_public)
	);
	// 공개 → 비공개 전환은 게시판 글쓰기가 막히고 이름 표시가 사라지므로 따로 알려 준다.
	const turningPrivate = $derived(!!me && me.is_info_public && !infoPublic);

	// 전화번호: 숫자만 추출 후 보기 좋게 하이픈 포맷 (/profile/complete 와 같은 규칙)
	function formatPhone(raw: string): string {
		const d = raw.replace(/\D/g, '');
		if (d.length === 11) return `${d.slice(0, 3)}-${d.slice(3, 7)}-${d.slice(7)}`;
		if (d.length === 10) return `${d.slice(0, 3)}-${d.slice(3, 6)}-${d.slice(6)}`;
		return d;
	}

	function fill(u: Me) {
		me = u;
		name = u.name ?? '';
		phone = u.phone ?? '';
		birthDate = u.birth_date ?? '';
		gender = u.gender ?? '';
		infoPublic = u.is_info_public;
	}

	const COLS =
		'id, email, name, phone, profile_picture, gender, birth_date, office, member, active, created_at, is_info_public, privacy_consented_at, roles(name, level)';

	onMount(async () => {
		const { data: { session } } = await supabaseBrowser.auth.getSession();
		if (!session) return goto('/login');

		const { data, error } = await supabaseBrowser
			.from('custom_users')
			.select(COLS)
			.eq('auth_id', session.user.id)
			.maybeSingle();

		if (error) {
			errorMsg = '내 정보를 불러오지 못했습니다.';
		} else if (!data) {
			notFound = true;
		} else {
			fill(data as unknown as Me);
		}
		loading = false;
	});

	async function save(e: Event) {
		e.preventDefault();
		if (!me) return;
		msg = '';
		errorMsg = '';

		const cleanName = name.trim();
		if (!cleanName) {
			errorMsg = '이름을 입력해주세요.';
			return;
		}
		if (phoneDigits.length < 10 || phoneDigits.length > 11) {
			errorMsg = '전화번호를 정확히 입력해주세요. (예: 010-1234-5678)';
			return;
		}
		if (turningPrivate && !confirm('정보 공개 동의를 해제하면 게시판 글쓰기를 이용할 수 없고, 쓰신 글에 이름이 표시되지 않습니다. 계속할까요?')) {
			return;
		}

		saving = true;
		// 직분(office)·교인 여부(member)·권한(role)은 일부러 보내지 않는다 — 교회 사무실이 관리한다.
		const { error } = await supabaseBrowser
			.from('custom_users')
			.update({
				name: cleanName,
				phone: formatPhone(phone),
				birth_date: birthDate || null,
				gender: gender || null,
				is_info_public: infoPublic
			})
			.eq('id', me.id);

		// 이름·전화번호를 바꾸면 AFTER 트리거 merge_user_data 가 같은 이름+전화의 비활성 프로필과
		// 병합하면서 직분·교인 여부·생년월일·성별까지 바꿀 수 있다. AFTER 트리거라 UPDATE 의
		// RETURNING 에는 안 잡히므로 반드시 따로 다시 읽어야 화면이 실제 값과 맞는다.
		const { data } = await supabaseBrowser
			.from('custom_users')
			.select(COLS)
			.eq('id', me.id)
			.maybeSingle();
		saving = false;

		if (error) {
			errorMsg = '저장에 실패했습니다. ' + error.message;
			return;
		}
		if (data) fill(data as unknown as Me);
		msg = '저장했습니다.';
	}

	function reset() {
		if (me) fill(me);
		msg = '';
		errorMsg = '';
	}
</script>

<svelte:head><title>내 정보 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-3xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
	<h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">내 정보</h1>
	<p class="text-gray-500 mb-8 text-sm sm:text-base">등록된 내 정보를 확인하고 수정할 수 있습니다.</p>

	{#if loading}
		<div class="py-20 text-center text-gray-400">불러오는 중…</div>
	{:else if notFound}
		<div class="py-20 text-center">
			<p class="text-gray-500 font-medium">프로필 정보가 아직 없습니다.</p>
			<a href="/profile/complete" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">프로필 입력하기</a>
		</div>
	{:else if me}
		<!-- 프로필 요약 -->
		<div class="flex items-center gap-4 mb-8">
			<div class="w-16 h-16 rounded-full overflow-hidden bg-gray-100 shrink-0 flex items-center justify-center">
				{#if me.profile_picture}
					<img src={me.profile_picture} alt="프로필" class="w-full h-full object-cover" />
				{:else}
					<span class="text-xl font-black text-gray-400">{(me.name ?? '?').slice(0, 1)}</span>
				{/if}
			</div>
			<div class="min-w-0">
				<div class="flex items-center gap-2 flex-wrap">
					<span class="text-xl font-black text-gray-900">{me.name ?? '이름 없음'}</span>
					<span class="text-xs font-bold text-primary-700 bg-primary-50 px-2 py-0.5 rounded">{me.office}</span>
					{#if !me.active}
						<span class="text-xs font-bold text-gray-500 bg-gray-100 px-2 py-0.5 rounded">비활성</span>
					{/if}
				</div>
				<!-- 사진은 카카오 계정에서 가져온다 — 여기서는 바꿀 수 없다 -->
				<p class="text-xs text-gray-400 mt-1">프로필 사진은 카카오 계정 사진을 사용합니다.</p>
			</div>
		</div>

		{#if msg}
			<div class="mb-5 bg-green-50 border border-green-100 text-green-700 text-sm rounded-xl px-4 py-3">{msg}</div>
		{/if}
		{#if errorMsg}
			<div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
		{/if}

		<!-- 교회가 관리하는 항목 (읽기 전용) -->
		<div class="rounded-2xl border border-gray-200 overflow-hidden mb-8">
			<div class="px-4 py-3 bg-gray-50 border-b border-gray-200">
				<span class="text-sm font-bold text-gray-700">교회 등록 정보</span>
				<span class="text-xs text-gray-500 ml-2">직접 수정할 수 없습니다. 변경이 필요하면 교회 사무실로 문의해 주세요.</span>
			</div>
			<dl class="divide-y divide-gray-100 text-sm">
				<div class="flex px-4 py-3">
					<dt class="w-32 shrink-0 font-bold text-gray-500">직분</dt>
					<dd class="text-gray-900">{me.office}</dd>
				</div>
				<div class="flex px-4 py-3">
					<dt class="w-32 shrink-0 font-bold text-gray-500">교인 등록</dt>
					<dd class="text-gray-900">{me.member ? '등록 교인' : '미등록'}</dd>
				</div>
				<div class="flex px-4 py-3">
					<dt class="w-32 shrink-0 font-bold text-gray-500">권한</dt>
					<dd class="text-gray-900">{roleName}</dd>
				</div>
				<div class="flex px-4 py-3">
					<dt class="w-32 shrink-0 font-bold text-gray-500">이메일</dt>
					<dd class="text-gray-900 break-all">{me.email ?? '-'}</dd>
				</div>
				<div class="flex px-4 py-3">
					<dt class="w-32 shrink-0 font-bold text-gray-500">가입일</dt>
					<dd class="text-gray-900">{fmtDay(me.created_at)}</dd>
				</div>
				<!-- 아래 '정보 공개 동의'(선택)와 다른 항목이다. 라벨을 '개인정보 동의'로만 두면
				     같은 것으로 읽혀서, 여기는 '기록 없음'인데 체크박스는 켜져 있는 게 모순처럼 보인다.
				     /profile/complete 와 같은 '수집·이용' 표현으로 맞춘다. -->
				<div class="flex px-4 py-3">
					<dt class="w-32 shrink-0 font-bold text-gray-500">개인정보 수집·이용 동의</dt>
					<dd class="text-gray-900">
						{me.privacy_consented_at ? fmtDay(me.privacy_consented_at) + ' 동의' : '동의 시점 기록 없음'}
						<a href="/privacy" class="ml-2 text-xs text-primary-700 underline">처리방침</a>
						{#if !me.privacy_consented_at}
							<!-- 동의를 안 했다는 뜻이 아니다 — 2026-06-28 부터 시점을 남기기 시작했다.
							     그 전 가입자(대부분)가 '기록 없음'만 보면 불안하게 읽힌다. -->
							<p class="text-xs text-gray-400 mt-0.5">
								2026년 6월 이전에 가입하셔서 동의 시점이 따로 저장되지 않았습니다.
							</p>
						{/if}
					</dd>
				</div>
			</dl>
		</div>

		<!-- 내가 고칠 수 있는 항목 -->
		<form onsubmit={save} class="rounded-2xl border border-gray-200 overflow-hidden">
			<div class="px-4 py-3 bg-gray-50 border-b border-gray-200">
				<span class="text-sm font-bold text-gray-700">내가 수정할 수 있는 정보</span>
			</div>
			<div class="p-4 sm:p-6 space-y-5">
				<div>
					<label for="p-name" class="block text-sm font-bold text-gray-700 mb-2">
						이름 <span class="text-gray-400 font-normal">(본명)</span>
					</label>
					<input id="p-name" type="text" bind:value={name} autocomplete="name"
						class="w-full px-4 py-3 rounded-2xl border border-gray-200 text-gray-900 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent text-base" />
					<p class="mt-1.5 text-xs text-gray-400">소그룹·출석 명단과 연결되므로 본명으로 입력해 주세요.</p>
				</div>

				<div>
					<label for="p-phone" class="block text-sm font-bold text-gray-700 mb-2">전화번호</label>
					<input id="p-phone" type="tel" inputmode="numeric" bind:value={phone} placeholder="010-1234-5678" autocomplete="tel"
						class="w-full px-4 py-3 rounded-2xl border border-gray-200 text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent text-base" />
				</div>

				<div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
					<div>
						<label for="p-birth" class="block text-sm font-bold text-gray-700 mb-2">
							생년월일 <span class="text-gray-400 font-normal">(선택)</span>
						</label>
						<input id="p-birth" type="date" bind:value={birthDate} max="2100-12-31"
							class="w-full px-4 py-3 rounded-2xl border border-gray-200 text-gray-900 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent text-base" />
					</div>
					<div>
						<label for="p-gender" class="block text-sm font-bold text-gray-700 mb-2">
							성별 <span class="text-gray-400 font-normal">(선택)</span>
						</label>
						<select id="p-gender" bind:value={gender}
							class="w-full px-4 py-3 rounded-2xl border border-gray-200 text-gray-900 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent text-base bg-white">
							<option value="">선택 안 함</option>
							<option value="남">남</option>
							<option value="여">여</option>
						</select>
					</div>
				</div>

				<div class="flex items-start gap-2.5 pt-1">
					<input id="p-public" type="checkbox" bind:checked={infoPublic}
						class="mt-0.5 w-4 h-4 rounded border-gray-300 text-primary-600 focus:ring-primary-500 shrink-0" />
					<div class="text-sm leading-snug">
						<label for="p-public" class="font-medium text-gray-800">[선택] 정보 공개 동의</label>
						<p class="text-xs text-gray-400 mt-0.5">
							게시판 글에 이름·직분이 표시되고, 소그룹 리더가 연락처를 볼 수 있습니다.
							동의하셔야 게시판 글쓰기를 이용할 수 있어요.
							<br />위 '개인정보 수집·이용 동의'와는 별개 항목입니다.
						</p>
						{#if turningPrivate}
							<p class="text-xs font-bold text-amber-600 mt-1.5">
								해제하면 게시판 글쓰기가 막히고, 쓰신 글에 이름이 표시되지 않습니다.
							</p>
						{/if}
					</div>
				</div>
			</div>

			<div class="flex items-center gap-2 px-4 sm:px-6 py-4 bg-gray-50 border-t border-gray-200">
				<button type="submit" disabled={!dirty || saving}
					class="px-6 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-40">
					{saving ? '저장 중…' : '저장'}
				</button>
				<button type="button" onclick={reset} disabled={!dirty || saving}
					class="px-4 py-2.5 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-white disabled:opacity-40">
					되돌리기
				</button>
			</div>
		</form>

		<div class="mt-6 flex flex-wrap gap-2">
			<a href="/parking/my" class="px-4 py-2 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50">내 차량 등록 →</a>
			<a href="/privacy" class="px-4 py-2 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50">개인정보처리방침 →</a>
		</div>
	{/if}
</div>
