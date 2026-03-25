<script lang="ts">
	import "./layout.css";
	import Header from "$lib/components/Header.svelte";
	import Footer from "$lib/components/Footer.svelte";
	import ScrollToTop from "$lib/components/ScrollToTop.svelte";

	let { children } = $props();
</script>

<svelte:head><link rel="icon" href="/favicon.png" type="image/png" /></svelte:head>

<div class="min-h-screen flex flex-col pt-20">
	<Header />

	<main class="grow flex flex-col w-full">
		{@render children()}
	</main>

	<Footer />
</div>

<ScrollToTop />
