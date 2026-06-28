<script lang="ts">
	import { onMount } from 'svelte';
	import { supabaseBrowser } from '$lib/supabase-browser';
	import { isProfileComplete } from '$lib/profile';
	import { goto } from '$app/navigation';

	let status = $state<'loading' | 'error'>('loading');
	let errorMsg = $state('');

	onMount(async () => {
		const code = new URLSearchParams(window.location.search).get('code');
		if (code) {
			const { error } = await supabaseBrowser.auth.exchangeCodeForSession(code);
			if (error) {
				status = 'error';
				errorMsg = error.message;
				return;
			}
		}
		// 프로필(이름·전화) 미완성이면 입력 페이지로. 여기서 목적지를 정해
		// 레이아웃 가드의 redirect 와 경쟁(서로 다른 곳으로 이동)하지 않게 한다.
		const {
			data: { session }
		} = await supabaseBrowser.auth.getSession();
		if (session && !(await isProfileComplete(session.user.id))) {
			goto('/profile/complete');
			return;
		}
		goto('/');
	});
</script>

<svelte:head>
	<title>로그인 중 - 부평동부교회</title>
</svelte:head>

<div class="flex-1 flex items-center justify-center py-20">
	{#if status === 'loading'}
		<div class="text-center space-y-4">
			<div class="w-12 h-12 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin mx-auto"></div>
			<p class="text-gray-500 font-medium">로그인 처리 중...</p>
		</div>
	{:else}
		<div class="text-center space-y-4">
			<p class="text-red-500 font-medium">{errorMsg}</p>
			<a href="/login" class="text-primary-600 font-bold hover:underline">다시 로그인</a>
		</div>
	{/if}
</div>
