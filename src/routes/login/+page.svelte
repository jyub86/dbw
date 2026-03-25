<script lang="ts">
	import { supabaseBrowser } from '$lib/supabase-browser';
	// import { goto } from '$app/navigation';

	// let { data } = $props();
	// const { loginSettings } = data;

	// let email = $state('');
	// let password = $state('');
	let loading = $state(false);
	let errorMsg = $state('');

	const origin = typeof window !== 'undefined' ? window.location.origin : '';

	async function loginWithKakao() {
		loading = true;
		errorMsg = '';
		const { error } = await supabaseBrowser.auth.signInWithOAuth({
			provider: 'kakao',
			options: { redirectTo: `${origin}/auth/callback` }
		});
		if (error) {
			errorMsg = error.message;
			loading = false;
		}
	}

	// async function loginWithOAuth(provider: 'kakao' | 'google' | 'apple') {
	// 	loading = true;
	// 	errorMsg = '';
	// 	const { error } = await supabaseBrowser.auth.signInWithOAuth({
	// 		provider,
	// 		options: { redirectTo: `${origin}/auth/callback` }
	// 	});
	// 	if (error) {
	// 		errorMsg = error.message;
	// 		loading = false;
	// 	}
	// }

	// async function loginWithEmail() {
	// 	loading = true;
	// 	errorMsg = '';
	// 	const { error } = await supabaseBrowser.auth.signInWithPassword({ email, password });
	// 	loading = false;
	// 	if (error) {
	// 		errorMsg = error.message;
	// 	} else {
	// 		goto('/');
	// 	}
	// }
</script>

<svelte:head>
	<title>로그인 - 부평동부교회</title>
</svelte:head>

<div class="flex-1 flex items-center justify-center py-20 px-4">
	<div class="w-full max-w-sm">
		<div class="text-center mb-10">
			<h1 class="text-3xl font-black text-gray-900 tracking-tight">로그인</h1>
			<p class="mt-2 text-gray-500">부평동부교회 계정으로 로그인하세요</p>
		</div>

		<div class="bg-white rounded-3xl shadow-sm border border-gray-100 p-8 space-y-4">
			{#if errorMsg}
				<div class="bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">
					{errorMsg}
				</div>
			{/if}

			<button
				onclick={loginWithKakao}
				disabled={loading}
				class="w-full flex items-center justify-center gap-3 py-3.5 px-4 rounded-2xl font-bold text-base bg-[#FEE500] text-[#191919] hover:bg-[#f0d800] transition-colors disabled:opacity-50"
			>
				<svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
					<path d="M12 3C6.477 3 2 6.582 2 11c0 2.836 1.698 5.328 4.275 6.865L5.25 21l4.085-2.19C10.1 18.93 11.03 19 12 19c5.523 0 10-3.582 10-8s-4.477-8-10-8z"/>
				</svg>
				카카오로 로그인
			</button>

			<!-- {#if loginSettings.google}
				<button
					onclick={() => loginWithOAuth('google')}
					disabled={loading}
					class="w-full flex items-center justify-center gap-3 py-3.5 px-4 rounded-2xl font-bold text-base bg-white text-gray-700 border border-gray-200 hover:bg-gray-50 transition-colors disabled:opacity-50"
				>
					<svg class="w-5 h-5" viewBox="0 0 24 24">
						<path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
						<path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
						<path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
						<path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
					</svg>
					Google로 로그인
				</button>
			{/if} -->

			<!-- {#if loginSettings.apple}
				<button
					onclick={() => loginWithOAuth('apple')}
					disabled={loading}
					class="w-full flex items-center justify-center gap-3 py-3.5 px-4 rounded-2xl font-bold text-base bg-black text-white hover:bg-gray-900 transition-colors disabled:opacity-50"
				>
					<svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
						<path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.7 9.05 7.4c1.29.07 2.18.74 2.93.8.89-.19 1.73-.82 2.64-.86 1.23-.06 2.26.42 2.92 1.15-2.64 1.57-2.22 5.63.3 7.05-.52 1.3-1.18 2.55-1.79 4.74zM12.03 7.25c-.13-2.27 1.8-4.12 3.93-4.25.29 2.56-2.32 4.43-3.93 4.25z"/>
					</svg>
					Apple로 로그인
				</button>
			{/if} -->

			<!-- {#if loginSettings.email}
				{#if loginSettings.kakao || loginSettings.google || loginSettings.apple}
					<div class="flex items-center gap-3 my-2">
						<div class="flex-1 h-px bg-gray-200"></div>
						<span class="text-sm text-gray-400 font-medium">또는</span>
						<div class="flex-1 h-px bg-gray-200"></div>
					</div>
				{/if}
				<form onsubmit={(e) => { e.preventDefault(); loginWithEmail(); }} class="space-y-3">
					<input
						type="email"
						bind:value={email}
						placeholder="이메일"
						required
						class="w-full px-4 py-3.5 rounded-2xl border border-gray-200 text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent text-base"
					/>
					<input
						type="password"
						bind:value={password}
						placeholder="비밀번호"
						required
						class="w-full px-4 py-3.5 rounded-2xl border border-gray-200 text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent text-base"
					/>
					<button
						type="submit"
						disabled={loading}
						class="w-full py-3.5 px-4 rounded-2xl font-bold text-base bg-primary-600 text-white hover:bg-primary-700 transition-colors disabled:opacity-50"
					>
						이메일로 로그인
					</button>
				</form>
			{/if} -->
		</div>
	</div>
</div>
