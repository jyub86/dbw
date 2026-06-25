<script lang="ts">
	import "./layout.css";
	import { page } from "$app/stores";
	import Header from "$lib/components/Header.svelte";
	import Footer from "$lib/components/Footer.svelte";
	import ScrollToTop from "$lib/components/ScrollToTop.svelte";

	let { children } = $props();

	// 라우트별 PWA manifest: /attendance 는 출석부 전용(홈 화면 추가 시 출석부로 바로 열림)
	const isAttendance = $derived($page.url.pathname.startsWith("/attendance"));
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
