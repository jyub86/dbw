<script lang="ts">
	import { page } from "$app/stores";
	import { onMount } from "svelte";
	import { supabaseBrowser } from "$lib/supabase-browser";

	let navOpen = $state(false);
	let scrolled = $state(false);
	let profilePicture = $state<string | null>(null);
	let isLoggedIn = $state(false);
	let dropdownOpen = $state(false);

	async function logout() {
		dropdownOpen = false;
		await supabaseBrowser.auth.signOut();
	}

	const menus = [
		{ name: "교회 소개", href: "/about" },
		{ name: "영상", href: "/videos" },
		{ name: "교회 소식", href: "/news" },
		{ name: "게시판", href: "/board" },
	];

	function toggleNav() {
		navOpen = !navOpen;
		if (navOpen) {
			document.body.style.overflow = "hidden";
		} else {
			document.body.style.overflow = "";
		}
	}

	async function loadProfile(userId: string) {
		const { data } = await supabaseBrowser
			.from("custom_users")
			.select("profile_picture")
			.eq("auth_id", userId)
			.single();
		profilePicture = data?.profile_picture ?? null;
	}

	onMount(() => {
		const handleScroll = () => {
			scrolled = window.scrollY > 20;
		};
		window.addEventListener("scroll", handleScroll);
		handleScroll();

		supabaseBrowser.auth.getSession().then(({ data: { session } }) => {
			isLoggedIn = !!session;
			if (session) loadProfile(session.user.id);
		});

		const { data: { subscription } } = supabaseBrowser.auth.onAuthStateChange((_event, session) => {
			isLoggedIn = !!session;
			if (session) loadProfile(session.user.id);
			else profilePicture = null;
		});

		const handleClickOutside = (e: MouseEvent) => {
			if (dropdownOpen && !(e.target as Element).closest('.profile-dropdown')) {
				dropdownOpen = false;
			}
		};
		window.addEventListener("click", handleClickOutside);

		return () => {
			window.removeEventListener("scroll", handleScroll);
			window.removeEventListener("click", handleClickOutside);
			subscription.unsubscribe();
		};
	});
</script>

<header
	class="fixed top-0 left-0 w-full z-50 transition-all duration-500 {scrolled
		? 'bg-white/90 backdrop-blur-lg shadow-sm py-2'
		: 'bg-transparent py-6'}"
>
	<div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12">
		<div class="flex items-center justify-between">
			<!-- Logo (Left) -->
			<div class="flex-1 md:w-1/4 flex justify-start z-50">
				<a href="/" class="flex items-center">
					<img src="/logo.png" alt="부평동부교회" class="h-10 md:h-12 w-auto" />
				</a>
			</div>

			<!-- Desktop Nav (Center) -->
			<nav class="hidden md:flex md:w-2/4 justify-center space-x-12">
				{#each menus as menu}
					<a
						href={menu.href}
						class="relative text-lg font-bold group py-2
						{scrolled || $page.url.pathname !== '/'
							? 'text-gray-700 hover:text-primary-600'
							: 'text-white/90 hover:text-white'}
						{$page.url.pathname.startsWith(menu.href) &&
						(scrolled || $page.url.pathname !== '/')
							? 'text-primary-600'
							: ''}"
					>
						{menu.name}
						<!-- Hover Underline -->
						<span
							class="absolute bottom-0 left-0 w-full h-[3px] bg-primary-500 transform scale-x-0 group-hover:scale-x-100 transition-transform duration-300 origin-center {$page.url.pathname.startsWith(
								menu.href,
							)
								? 'scale-x-100'
								: ''}"
						></span>
					</a>
				{/each}
			</nav>

			<!-- Right Actions / Mobile Toggle -->
			<div class="w-auto md:w-1/4 flex justify-end z-50">
				<div class="hidden md:flex items-center">
						{#if isLoggedIn}
						<div class="relative profile-dropdown">
							<button
								onclick={() => dropdownOpen = !dropdownOpen}
								class="w-9 h-9 rounded-full overflow-hidden border-2 border-white/30 hover:border-white transition-colors flex items-center justify-center bg-gray-200 shrink-0"
							>
								{#if profilePicture}
									<img src={profilePicture} alt="프로필" class="w-full h-full object-cover" />
								{:else}
									<svg class="w-5 h-5 text-gray-500" fill="currentColor" viewBox="0 0 24 24">
										<path d="M12 12c2.7 0 4.8-2.1 4.8-4.8S14.7 2.4 12 2.4 7.2 4.5 7.2 7.2 9.3 12 12 12zm0 2.4c-3.2 0-9.6 1.6-9.6 4.8v2.4h19.2v-2.4c0-3.2-6.4-4.8-9.6-4.8z"/>
									</svg>
								{/if}
							</button>
							{#if dropdownOpen}
								<div
									role="menu"
									tabindex="-1"
									class="absolute right-0 top-12 w-36 bg-white rounded-2xl shadow-xl border border-gray-100 py-1 z-50"
									onmouseleave={() => dropdownOpen = false}
								>
									<button onclick={logout} class="w-full text-left px-4 py-2.5 text-sm font-medium text-red-500 hover:bg-red-50 rounded-b-2xl">
										로그아웃
									</button>
								</div>
							{/if}
						</div>
					{:else}
						<a
							href="/login"
							class="px-5 py-2 rounded-full font-bold text-sm border-2 transition-colors
							{scrolled || $page.url.pathname !== '/'
								? 'border-gray-900 text-gray-900 hover:bg-gray-900 hover:text-white'
								: 'border-white text-white hover:bg-white hover:text-gray-900'}"
						>
							로그인
						</a>
					{/if}
				</div>
				<!-- Mobile menu button -->
				<button
					type="button"
					onclick={toggleNav}
					class="md:hidden inline-flex items-center justify-center p-2 rounded-full text-gray-900 hover:bg-gray-100 transition-colors focus:outline-none"
				>
					<span class="sr-only">Open menu</span>
					<div
						class="w-6 h-5 relative flex flex-col justify-between transform transition-all duration-300 {navOpen
							? 'rotate-180'
							: ''}"
					>
						<span
							class="w-full h-0.5 bg-gray-900 transform transition-all duration-300 {navOpen
								? 'rotate-45 translate-y-2.5'
								: ''}"
						></span>
						<span
							class="w-full h-0.5 bg-gray-900 transition-all duration-300 {navOpen ? 'opacity-0' : ''}"
						></span>
						<span
							class="w-full h-0.5 bg-gray-900 transform transition-all duration-300 {navOpen
								? '-rotate-45 -translate-y-2'
								: ''}"
						></span>
					</div>
				</button>
			</div>
		</div>
	</div>

	<!-- Premium Mobile Menu Fullscreen Overlay -->
	<div
		class="fixed inset-0 bg-white z-40 transition-all duration-500 ease-in-out md:hidden flex flex-col justify-center px-8 overflow-y-auto {navOpen
			? 'opacity-100 visible'
			: 'opacity-0 invisible'}"
	>
		<nav class="flex flex-col space-y-8 text-center mt-12">
			{#each menus as menu, i}
				<a
					href={menu.href}
					onclick={toggleNav}
					class="text-3xl sm:text-4xl font-black text-gray-900 hover:text-primary-600 transition-colors transform {navOpen
						? 'translate-y-0 opacity-100'
						: 'translate-y-8 opacity-0'}"
					style="transition-delay: {i * 100 + 100}ms;"
				>
					{menu.name}
				</a>
			{/each}
		</nav>
		<div
			class="mt-12 text-center transform {navOpen
				? 'translate-y-0 opacity-100'
				: 'translate-y-8 opacity-0'}"
			style="transition-delay: 500ms;"
		>
			{#if isLoggedIn}
				<button
					onclick={async () => { await logout(); toggleNav(); }}
					class="inline-block px-10 py-3.5 rounded-full font-bold text-base border-2 border-red-200 text-red-500 hover:bg-red-50 transition-colors"
				>
					로그아웃
				</button>
			{:else}
				<a
					href="/login"
					onclick={toggleNav}
					class="inline-block px-10 py-3.5 rounded-full font-bold text-base border-2 border-gray-900 text-gray-900 hover:bg-gray-900 hover:text-white transition-colors"
				>
					로그인
				</a>
			{/if}
		</div>
		<div
			class="mt-8 text-center transform {navOpen
				? 'translate-y-0 opacity-100'
				: 'translate-y-8 opacity-0'}"
			style="transition-delay: 600ms;"
		>
			<p class="text-gray-500 font-medium">인천광역시 부평구 시장로 64</p>
			<p class="text-gray-500 font-medium mt-2">032-515-1401</p>
		</div>
	</div>
</header>
