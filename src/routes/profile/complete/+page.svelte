<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabaseBrowser } from '$lib/supabase-browser';

	let loading = $state(true);
	let saving = $state(false);
	let errorMsg = $state('');

	let authId = $state('');
	let name = $state('');
	let phone = $state('');
	let agreePrivacy = $state(false); // [필수] 개인정보 수집·이용 동의
	let agreeInfoPublic = $state(false); // [선택] 정보 공개 동의 → is_info_public

	onMount(async () => {
		const {
			data: { session }
		} = await supabaseBrowser.auth.getSession();
		if (!session) {
			goto('/login');
			return;
		}
		authId = session.user.id;

		// 기존 행이 있으면 값 미리 채우기
		const { data: me } = await supabaseBrowser
			.from('custom_users')
			.select('name, phone')
			.eq('auth_id', authId)
			.maybeSingle();

		// 카카오 닉네임이 본명과 다를 가능성이 높아 일부러 미리 채우지 않음(본명을 직접 입력하도록).
		name = '';
		phone = me?.phone?.trim() || '';

		// 이미 둘 다 채워져 있으면 굳이 여기 있을 필요 없음
		if (me?.name?.trim() && me?.phone?.trim()) {
			goto('/');
			return;
		}
		loading = false;
	});

	// 전화번호: 숫자만 추출 후 보기 좋게 하이픈 포맷
	function formatPhone(raw: string): string {
		const d = raw.replace(/\D/g, '');
		if (d.length === 11) return `${d.slice(0, 3)}-${d.slice(3, 7)}-${d.slice(7)}`;
		if (d.length === 10) return `${d.slice(0, 3)}-${d.slice(3, 6)}-${d.slice(6)}`;
		return d;
	}

	async function handleSubmit(e: Event) {
		e.preventDefault();
		errorMsg = '';

		const cleanName = name.trim();
		const digits = phone.replace(/\D/g, '');
		if (!cleanName) {
			errorMsg = '이름을 입력해주세요.';
			return;
		}
		if (digits.length < 10 || digits.length > 11) {
			errorMsg = '전화번호를 정확히 입력해주세요. (예: 010-1234-5678)';
			return;
		}
		if (!agreePrivacy) {
			errorMsg = '개인정보 수집·이용 동의(필수)에 체크해주세요.';
			return;
		}

		saving = true;
		const profileData = {
			name: cleanName,
			phone: formatPhone(phone),
			is_info_public: agreeInfoPublic,
			privacy_consented_at: new Date().toISOString()
		};

		// 행이 없으면 먼저 생성. (welcome_new_user 트리거가 NEW.name 으로 메시지를 만들기 때문에
		// name 을 채운 채로 insert 해야 함. merge_user_data 는 UPDATE 에만 작동하므로
		// insert 후 아래 UPDATE 에서 병합이 일어남.)
		const { data: existing } = await supabaseBrowser
			.from('custom_users')
			.select('id')
			.eq('auth_id', authId)
			.maybeSingle();

		if (!existing) {
			const { error: insErr } = await supabaseBrowser
				.from('custom_users')
				.insert({ auth_id: authId, active: true, ...profileData });
			// 동시성으로 이미 생성됐을 수 있음 → 무시하고 UPDATE 진행
			if (insErr && insErr.code !== '23505') {
				errorMsg = '저장에 실패했습니다. 다시 시도해주세요.';
				saving = false;
				return;
			}
		}

		// UPDATE → merge_user_data 트리거가 동일 이름+전화 더미(active=false)와 병합
		const { error: updErr } = await supabaseBrowser
			.from('custom_users')
			.update(profileData)
			.eq('auth_id', authId);

		if (updErr) {
			errorMsg = '저장에 실패했습니다. 다시 시도해주세요.';
			saving = false;
			return;
		}

		goto('/');
	}
</script>

<svelte:head>
	<title>프로필 입력 - 부평동부교회</title>
</svelte:head>

<div class="flex-1 flex items-center justify-center py-20 px-4">
	<div class="w-full max-w-sm">
		<div class="text-center mb-8">
			<h1 class="text-2xl sm:text-3xl font-black text-gray-900 tracking-tight">프로필 입력</h1>
			<p class="mt-2 text-gray-500 text-sm leading-relaxed">
				소속 소그룹·직분과 연결하기 위해<br />본명과 전화번호를 입력해주세요.
			</p>
		</div>

		{#if loading}
			<div class="py-16 text-center text-gray-400">불러오는 중…</div>
		{:else}
			<div class="bg-white rounded-3xl shadow-sm border border-gray-100 p-8 space-y-5">
				{#if errorMsg}
					<div class="bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
				{/if}

				<form onsubmit={handleSubmit} class="space-y-4">
					<div>
						<label for="name" class="block text-sm font-bold text-gray-700 mb-2">
							이름 <span class="text-gray-400 font-normal">(본명)</span>
						</label>
						<input
							id="name"
							type="text"
							bind:value={name}
							placeholder="실제 이름"
							autocomplete="name"
							class="w-full px-4 py-3.5 rounded-2xl border border-gray-200 text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent text-base"
						/>
					</div>
					<div>
						<label for="phone" class="block text-sm font-bold text-gray-700 mb-2">전화번호</label>
						<input
							id="phone"
							type="tel"
							inputmode="numeric"
							bind:value={phone}
							placeholder="010-1234-5678"
							autocomplete="tel"
							class="w-full px-4 py-3.5 rounded-2xl border border-gray-200 text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent text-base"
						/>
					</div>

					<div class="space-y-3 pt-1">
						<div class="flex items-start gap-2.5">
							<input id="agree-privacy" type="checkbox" bind:checked={agreePrivacy}
								class="mt-0.5 w-4 h-4 rounded border-gray-300 text-primary-600 focus:ring-primary-500 shrink-0" />
							<div class="text-sm leading-snug">
								<label for="agree-privacy" class="font-medium text-gray-800">[필수] 개인정보 수집·이용 동의</label>
								<a href="/privacy" target="_blank" rel="noopener" class="ml-1 text-xs text-primary-700 underline">자세히</a>
								<p class="text-xs text-gray-400 mt-0.5">이름·전화번호를 소그룹·출석·교적 관리에 이용합니다.</p>
							</div>
						</div>
						<div class="flex items-start gap-2.5">
							<input id="agree-public" type="checkbox" bind:checked={agreeInfoPublic}
								class="mt-0.5 w-4 h-4 rounded border-gray-300 text-primary-600 focus:ring-primary-500 shrink-0" />
							<div class="text-sm leading-snug">
								<label for="agree-public" class="font-medium text-gray-800">[선택] 정보 공개 동의</label>
								<p class="text-xs text-gray-400 mt-0.5">
									게시판 글에 이름·직분이 표시되고, 소그룹 리더가 연락처를 볼 수 있습니다.
									동의하셔야 게시판 글쓰기를 이용할 수 있어요.
								</p>
							</div>
						</div>
					</div>

					<button
						type="submit"
						disabled={saving}
						class="w-full py-3.5 px-4 rounded-2xl font-bold text-base bg-primary-900 text-white hover:bg-primary-800 transition-colors disabled:opacity-50"
					>
						{saving ? '저장 중…' : '저장하고 시작하기'}
					</button>
				</form>
			</div>
		{/if}
	</div>
</div>
