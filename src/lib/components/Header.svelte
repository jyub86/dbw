<script lang="ts">
	import { page } from "$app/stores";
	import { onMount } from "svelte";
	import { supabaseBrowser } from "$lib/supabase-browser";

	let navOpen = $state(false);
	let scrolled = $state(false);
	let isLoggedIn = $state(false);
	let dropdownOpen = $state(false);
	let openGroup = $state<string | null>(null);
	let isAdmin = $state(false);
	let canSeeAttendance = $state(false);
	let canSeeEducation = $state(false);
	let canSeeParking = $state(false);
	let canSeeExport = $state(false);
	let registryHref = $state<string | null>(null);

	async function logout() {
		dropdownOpen = false;
		await supabaseBrowser.auth.signOut();
	}

	type NavItem = { name: string; href: string };
	// href 가 있으면 바로 가는 링크, items 가 있으면 드롭다운.
	type NavEntry = { name: string; href?: string; items?: NavItem[] };

	// 관리자는 상단에 10개(공개 7 + 업무 3)가 들어가 1280px 에서도 꽉 찼다.
	// 성격별로 묶어 최상위를 4개로 줄인다. 업무 화면은 '관리' 하나로 모은다 —
	// 전에는 출석부·교육부서·주차 관리는 네비에, 자료 내보내기·변경 로그는 계정
	// 드롭다운에 있어서 같은 성격의 화면이 두 군데로 쪼개져 있었다.
	const manageItems = $derived<NavItem[]>([
		...(canSeeAttendance ? [{ name: "출석부", href: "/attendance" }] : []),
		...(canSeeEducation ? [{ name: "교육부서", href: "/education" }] : []),
		// '주차' 만 쓰면 이 앱에서 흔한 '주차(week)' 와 헷갈려 '주차 관리' 로 둔다.
		...(canSeeParking ? [{ name: "주차 관리", href: "/parking" }] : []),
		...(registryHref ? [{ name: "교적", href: registryHref }] : []),
		...(canSeeExport ? [{ name: "자료 내보내기", href: "/export" }] : []),
		...(isAdmin ? [{ name: "변경 로그", href: "/logs" }] : []),
	]);

	const navEntries = $derived<NavEntry[]>([
		{
			name: "교회 안내",
			items: [
				{ name: "교회 소개", href: "/about" },
				{ name: "공동체", href: "/community" },
				{ name: "다음 세대", href: "/next-gen" },
			],
		},
		{
			name: "소식·미디어",
			items: [
				{ name: "교회 영상", href: "/videos" },
				{ name: "교회 소식", href: "/news" },
				{ name: "교회 일정", href: "/events" },
			],
		},
		{ name: "커뮤니티", href: "/board" },
		// 권한이 하나도 없으면 '관리' 자체를 띄우지 않는다
		...(manageItems.length ? [{ name: "관리", items: manageItems }] : []),
	]);

	const isActive = (href: string) => $page.url.pathname.startsWith(href);
	const entryActive = (e: NavEntry) =>
		e.href ? isActive(e.href) : (e.items ?? []).some((i) => isActive(i.href));

	// 모바일 오버레이는 등장 애니메이션 지연을 순번으로 준다 → 평평하게 펴서 번호를 매긴다.
	const mobileRows = $derived(
		navEntries.flatMap((e) =>
			e.href
				? [{ kind: "link" as const, name: e.name, href: e.href }]
				: [
						{ kind: "label" as const, name: e.name, href: "" },
						...(e.items ?? []).map((i) => ({ kind: "link" as const, ...i })),
					],
		),
	);

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
			.select("id, roles(level)")
			.eq("auth_id", userId)
			.single();

		// 출석부 메뉴 노출: 소그룹 리더 / 지정 교역자 / 통계 열람자 / 관리자(level>=100)
		const level = (data?.roles as unknown as { level: number } | null)?.level ?? 0;
		isAdmin = level >= 100;
		let allowed = isAdmin;
		if (data?.id && !allowed) {
			const { count } = await supabaseBrowser
				.from("small_group_members")
				.select("id", { count: "exact", head: true })
				.eq("user_id", data.id)
				.eq("role", "leader");
			allowed = (count ?? 0) > 0;
			if (!allowed) {
				const { count: mc } = await supabaseBrowser
					.from("attendance_managers")
					.select("user_id", { count: "exact", head: true })
					.eq("user_id", data.id);
				allowed = (mc ?? 0) > 0;
			}
			if (!allowed) {
				const { count: sc } = await supabaseBrowser
					.from("attendance_stat_viewers")
					.select("user_id", { count: "exact", head: true })
					.eq("user_id", data.id);
				allowed = (sc ?? 0) > 0;
			}
		}
		canSeeAttendance = allowed;

		// 교육부서 메뉴 노출: 관리자(level>=100) 또는 보고서 담당자
		let eduAllowed = isAdmin;
		if (data?.id && !eduAllowed) {
			const { count: ec } = await supabaseBrowser
				.from("education_report_editors")
				.select("user_id", { count: "exact", head: true })
				.eq("user_id", data.id);
			eduAllowed = (ec ?? 0) > 0;
		}
		canSeeEducation = eduAllowed;

		// 주차 관리 메뉴 노출: 관리자(level>=100) 또는 지정된 주차 담당자.
		// 관리자는 아래 조회를 건너뛴다.
		let parkAllowed = isAdmin;
		if (data?.id && !parkAllowed) {
			const { count: pc } = await supabaseBrowser
				.from("parking_managers")
				.select("user_id", { count: "exact", head: true })
				.eq("user_id", data.id);
			parkAllowed = (pc ?? 0) > 0;
		}
		canSeeParking = parkAllowed;

		// 자료 내보내기 메뉴 노출: 관리자 또는 export_users 에 지정된 사람
		let exportAllowed = isAdmin;
		if (data?.id && !exportAllowed) {
			const { count: xc } = await supabaseBrowser
				.from("export_users")
				.select("user_id", { count: "exact", head: true })
				.eq("user_id", data.id);
			exportAllowed = (xc ?? 0) > 0;
		}
		canSeeExport = exportAllowed;

		// 교적 메뉴 노출: 교적 권한자 → 교인 목록, 교적 권한 없는 사이트 관리자 → 권한 관리 화면
		const { data: reg } = await supabaseBrowser.rpc("registry_me");
		const r = reg as { is_staff?: boolean; is_admin?: boolean } | null;
		registryHref = r?.is_staff ? "/registry" : r?.is_admin ? "/registry/admin" : null;
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
			else { isAdmin = false; canSeeAttendance = false; canSeeEducation = false; canSeeParking = false; canSeeExport = false; registryHref = null; }
		});

		const handleClickOutside = (e: MouseEvent) => {
			const t = e.target as Element;
			if (dropdownOpen && !t.closest('.profile-dropdown')) {
				dropdownOpen = false;
			}
			// 터치·클릭으로 연 그룹 메뉴는 mouseleave 가 안 와서 안 닫힌다
			if (openGroup && !t.closest('.nav-group')) {
				openGroup = null;
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

<header class="fixed top-0 left-0 w-full z-50">
	<div class="relative z-50 transition-all duration-500 {scrolled ? 'bg-white/90 backdrop-blur-lg shadow-sm py-2' : 'bg-transparent py-6'}">
	<div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12">
		<div class="flex items-center justify-between">
			<!-- Logo (Left) -->
			<div class="shrink-0 flex justify-start z-50 mr-4">
				<a href="/" class="flex items-center">
					<img src="/logo2.png" alt="부평동부교회" class="h-10 md:h-12 w-auto" />
				</a>
			</div>

			<!-- Desktop Nav (Center) -->
			<nav class="hidden xl:flex xl:flex-1 justify-center space-x-8 xl:space-x-10">
				{#each navEntries as entry}
					{@const active = entryActive(entry)}
					{@const onDark = !scrolled && $page.url.pathname === '/'}
					{#if entry.href}
						<a
							href={entry.href}
							class="relative text-sm lg:text-base font-bold group py-2 whitespace-nowrap
							{onDark ? 'text-white/90 hover:text-white' : 'text-gray-700 hover:text-primary-600'}
							{active && !onDark ? 'text-primary-600' : ''}"
						>
							{entry.name}
							<!-- Hover Underline -->
							<span
								class="absolute bottom-0 left-0 w-full h-[3px] bg-primary-500 transform scale-x-0 group-hover:scale-x-100 transition-transform duration-300 origin-center {active
									? 'scale-x-100'
									: ''}"
							></span>
						</a>
					{:else}
						<!-- 마우스를 올리면 열린다. 패널이 이 div 의 자손이라 패널로 내려가도
						     mouseleave 가 터지지 않는다(자손으로 이동할 때는 발생하지 않음). -->
						<div
							class="nav-group relative"
							role="none"
							onmouseenter={() => (openGroup = entry.name)}
							onmouseleave={() => (openGroup = null)}
						>
							<button
								type="button"
								onclick={() => (openGroup = openGroup === entry.name ? null : entry.name)}
								class="relative flex items-center gap-1 text-sm lg:text-base font-bold group py-2 whitespace-nowrap
								{onDark ? 'text-white/90 hover:text-white' : 'text-gray-700 hover:text-primary-600'}
								{active && !onDark ? 'text-primary-600' : ''}"
							>
								{entry.name}
								<svg
									class="w-3.5 h-3.5 transition-transform duration-200 {openGroup === entry.name ? 'rotate-180' : ''}"
									fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"
								>
									<path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
								</svg>
								<span
									class="absolute bottom-0 left-0 w-full h-[3px] bg-primary-500 transform scale-x-0 group-hover:scale-x-100 transition-transform duration-300 origin-center {active
										? 'scale-x-100'
										: ''}"
								></span>
							</button>
							{#if openGroup === entry.name}
								<!-- pt-3 는 버튼과 패널 사이를 잇는 다리 — 비워 두면 그 틈에서 메뉴가 닫힌다 -->
								<div class="absolute left-1/2 -translate-x-1/2 top-full pt-3 z-50">
									<div class="min-w-[10rem] bg-white rounded-2xl shadow-xl border border-gray-100 py-1.5">
										{#each entry.items ?? [] as item}
											<a
												href={item.href}
												onclick={() => (openGroup = null)}
												class="block px-4 py-2.5 text-sm font-bold whitespace-nowrap hover:bg-gray-50 {isActive(item.href)
													? 'text-primary-600'
													: 'text-gray-700'}"
											>
												{item.name}
											</a>
										{/each}
									</div>
								</div>
							{/if}
						</div>
					{/if}
				{/each}
			</nav>

			<!-- Right Actions / Mobile Toggle -->
			<div class="shrink-0 flex justify-end relative z-50 ml-4">
				<div class="hidden xl:flex items-center">
						{#if isLoggedIn}
						<div class="relative profile-dropdown">
							<!-- 좁은 화면의 메뉴 버튼과 같은 햄버거 모양을 쓴다. 카카오 계정 사진을
							     없앤 뒤 원형 아바타만 남으니 화면 폭에 따라 버튼이 달라 보였다. -->
							<button
								type="button"
								onclick={() => dropdownOpen = !dropdownOpen}
								class="inline-flex items-center justify-center p-2 rounded-full text-gray-900 hover:bg-gray-100 transition-colors focus:outline-none"
							>
								<span class="sr-only">계정 메뉴</span>
								<div
									class="w-6 h-5 relative flex flex-col justify-between transform transition-all duration-300 {dropdownOpen
										? 'rotate-180'
										: ''}"
								>
									<span
										class="w-full h-0.5 bg-gray-900 transform transition-all duration-300 {dropdownOpen
											? 'rotate-45 translate-y-2.5'
											: ''}"
									></span>
									<span
										class="w-full h-0.5 bg-gray-900 transition-all duration-300 {dropdownOpen ? 'opacity-0' : ''}"
									></span>
									<span
										class="w-full h-0.5 bg-gray-900 transform transition-all duration-300 {dropdownOpen
											? '-rotate-45 -translate-y-2'
											: ''}"
									></span>
								</div>
							</button>
							{#if dropdownOpen}
								<div
									role="menu"
									tabindex="-1"
									class="absolute right-0 top-12 w-36 bg-white rounded-2xl shadow-xl border border-gray-100 py-1 z-50"
									onmouseleave={() => dropdownOpen = false}
								>
									<!-- 여기는 '내 것'만 둔다. 업무 화면(출석부·교육부서·주차 관리·
									     자료 내보내기·변경 로그)은 전부 네비의 '관리' 로 모았다. -->
									<a href="/profile" onclick={() => dropdownOpen = false} class="block px-4 py-2.5 text-sm font-medium text-gray-700 hover:bg-gray-50 rounded-t-2xl">
										내 정보
									</a>
									<a href="/parking/my" onclick={() => dropdownOpen = false} class="block px-4 py-2.5 text-sm font-medium text-gray-700 hover:bg-gray-50">
										내 차량
									</a>
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
					class="xl:hidden inline-flex items-center justify-center p-2 rounded-full text-gray-900 hover:bg-gray-100 transition-colors focus:outline-none"
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
	</div>

	<!-- Premium Mobile Menu Fullscreen Overlay -->
	<!--
	  바깥 div = 스크롤 담당, 안쪽 div = 가운데 정렬 담당. 한 요소에 둘을 같이 주면
	  (justify-center + overflow-y-auto) 내용이 화면보다 길 때 위쪽이 잘리고 스크롤로도
	  닿지 않는다. 메뉴 항목이 늘어 내용이 808px 가 된 지금 작은 폰에서 실제로 그랬다.
	  pt-28(112px) 은 고정 헤더 자리 — 헤더가 z-50 으로 이 위에 그려지므로(닫기 버튼이
	  헤더 안에 있어 가려지면 안 된다) 그만큼 비워 두지 않으면 첫 항목이 로고와 겹친다.
	  모바일 헤더는 로고 h-10 + py-6 = 88px 이라 24px 여유가 남는다.
	-->
	<div
		class="fixed inset-0 bg-white z-40 transition-all duration-500 ease-in-out xl:hidden overflow-y-auto {navOpen
			? 'opacity-100 visible'
			: 'opacity-0 invisible'}"
	>
	<div class="min-h-full flex flex-col justify-center px-8 pt-28 pb-12">
		<!-- 데스크톱의 묶음을 그대로 따라간다 — 그룹 이름은 작은 라벨, 실제 이동은 그 아래 항목.
		     라벨은 링크가 아니다(그룹 자체에는 갈 페이지가 없다). -->
		<nav class="flex flex-col text-center">
			{#each mobileRows as row, i}
				{#if row.kind === 'label'}
					<p
						class="mt-8 first:mt-0 mb-3 text-xs font-bold tracking-widest text-gray-400 transform {navOpen
							? 'translate-y-0 opacity-100'
							: 'translate-y-8 opacity-0'}"
						style="transition-delay: {i * 60 + 100}ms;"
					>
						{row.name}
					</p>
				{:else}
					<a
						href={row.href}
						onclick={toggleNav}
						class="py-2 text-2xl sm:text-3xl font-black transition-colors transform {isActive(row.href)
							? 'text-primary-600'
							: 'text-gray-900 hover:text-primary-600'} {navOpen
							? 'translate-y-0 opacity-100'
							: 'translate-y-8 opacity-0'}"
						style="transition-delay: {i * 60 + 100}ms;"
					>
						{row.name}
					</a>
				{/if}
			{/each}
		</nav>
		<div
			class="mt-12 text-center transform {navOpen
				? 'translate-y-0 opacity-100'
				: 'translate-y-8 opacity-0'}"
			style="transition-delay: 500ms;"
		>
			{#if isLoggedIn}
				<a
					href="/profile"
					onclick={toggleNav}
					class="inline-block px-10 py-3.5 mb-2 mr-2 rounded-full font-bold text-base border-2 border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors"
				>
					내 정보
				</a>
				<a
					href="/parking/my"
					onclick={toggleNav}
					class="inline-block px-10 py-3.5 mb-2 mr-2 rounded-full font-bold text-base border-2 border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors"
				>
					내 차량
				</a>
				<!-- 자료 내보내기·변경 로그는 위 '관리' 묶음으로 옮겼다 -->
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
	</div>
</header>
