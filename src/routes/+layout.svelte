<script lang="ts">
	import "./layout.css";
	import { onMount } from "svelte";
	import { page } from "$app/stores";
	import { goto } from "$app/navigation";
	import { supabaseBrowser } from "$lib/supabase-browser";
	import { isProfileComplete } from "$lib/profile";
	import Header from "$lib/components/Header.svelte";
	import Footer from "$lib/components/Footer.svelte";
	import ScrollToTop from "$lib/components/ScrollToTop.svelte";

	let { children } = $props();

	// 라우트별 PWA manifest: /attendance 는 출석부 전용(홈 화면 추가 시 출석부로 바로 열림)
	const isAttendance = $derived($page.url.pathname.startsWith("/attendance"));

	// 로그인 사용자인데 이름/전화가 없으면(또는 프로필 행 자체가 없으면) 입력 페이지로 유도.
	// 입력 후 UPDATE 가 merge_user_data 트리거를 발동시켜 기존 더미(active=false)와 병합됨.
	const PROFILE_EXEMPT = ["/profile/complete", "/login", "/auth/callback", "/privacy", "/terms"];

	async function ensureProfile() {
		const {
			data: { session }
		} = await supabaseBrowser.auth.getSession();
		if (!session) return;

		// 행이 없거나 이름/전화가 비어 있으면 입력 페이지로 유도 (예외 경로 제외).
		// 행 생성은 /profile/complete 에서 (미완료 이탈 시 빈 활성행이 남지 않도록),
		// 입력 시 UPDATE 로 merge_user_data 트리거가 동일 이름+전화 더미와 병합.
		const path = window.location.pathname;
		if (PROFILE_EXEMPT.some((p) => path.startsWith(p))) return;
		if (!(await isProfileComplete(session.user.id))) goto("/profile/complete");
	}

	onMount(() => {
		const { data: sub } = supabaseBrowser.auth.onAuthStateChange((event) => {
			if (event === "SIGNED_IN" || event === "INITIAL_SESSION") ensureProfile();
		});
		return () => sub.subscription.unsubscribe();
	});
</script>

<svelte:head>
	<link rel="icon" href="/favicon.png" type="image/png" />
	{#if isAttendance}
		<link rel="manifest" href="/attendance.webmanifest" />
		<meta name="apple-mobile-web-app-title" content="출석부" />
	{:else}
		<link rel="manifest" href="/site.webmanifest" />
		<meta name="apple-mobile-web-app-title" content="부평동부교회" />
	{/if}
</svelte:head>

<div class="min-h-screen flex flex-col pt-20">
	<Header />

	<main class="grow flex flex-col w-full">
		{@render children()}
	</main>

	<Footer />
</div>

<ScrollToTop />
