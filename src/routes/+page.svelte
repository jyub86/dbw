<script lang="ts">
    import { onMount, onDestroy } from 'svelte';

    let appLink = $state('https://play.google.com/store/search?q=부평동부교회&c=apps');
    let isApplePlatform = $state(false);

    onMount(() => {
        const ua = navigator.userAgent;
        if (/iphone|ipad|ipod|macintosh/i.test(ua)) {
            appLink = 'https://apps.apple.com/kr/search?term=부평동부교회';
            isApplePlatform = true;
        } else {
            appLink = 'https://play.google.com/store/search?q=부평동부교회&c=apps';
            isApplePlatform = false;
        }
    });

    let { data } = $props();
    const banners = $derived(data.banners);
    const videos = $derived(data.videos);

    let currentIndex = $state(0);
    let timer: ReturnType<typeof setInterval>;

    function startTimer() {
        clearInterval(timer);
        if (banners.length > 1) {
            timer = setInterval(() => {
                currentIndex = (currentIndex + 1) % banners.length;
            }, 10000);
        }
    }

    function goTo(index: number) {
        currentIndex = index;
        startTimer();
    }

    onMount(() => startTimer());
    onDestroy(() => clearInterval(timer));

    // 스와이프
    let dragStartX = 0;
    let dragged = false;

    function onPointerDown(e: MouseEvent | TouchEvent) {
        dragStartX = 'touches' in e ? e.touches[0].clientX : e.clientX;
        dragged = false;

        const onEnd = (ev: MouseEvent | TouchEvent) => {
            const endX = 'changedTouches' in ev ? ev.changedTouches[0].clientX : (ev as MouseEvent).clientX;
            const diff = dragStartX - endX;
            if (Math.abs(diff) >= 50) {
                dragged = true;
                goTo(diff > 0
                    ? (currentIndex + 1) % banners.length
                    : (currentIndex - 1 + banners.length) % banners.length
                );
            }
            window.removeEventListener('mouseup', onEnd as EventListener);
            window.removeEventListener('touchend', onEnd as EventListener);
        };

        window.addEventListener('mouseup', onEnd as EventListener, { once: true });
        window.addEventListener('touchend', onEnd as EventListener, { once: true });
    }

    function onLinkClick(e: MouseEvent) {
        if (dragged) {
            e.preventDefault();
            dragged = false;
        }
    }


    const latestNews = $derived(data.latestNews);
    const latestBoard = $derived(data.latestBoard);
</script>

<svelte:head>
    <title>부평동부교회</title>
</svelte:head>

<!-- 1. Hero Section - Banner Slideshow -->
<section aria-label="배너 슬라이드쇼" class="relative w-full aspect-video bg-gray-900 overflow-hidden md:-mt-24">
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
    <div
        aria-label="슬라이드 드래그 영역"
        class="absolute inset-0 select-none cursor-grab active:cursor-grabbing"
        onmousedown={onPointerDown}
        ontouchstart={onPointerDown}
    >
        {#if banners.length === 0}
            <div class="absolute inset-0 flex items-center justify-center">
                <p class="text-white text-2xl font-bold">부평동부교회</p>
            </div>
        {:else}
            {#each banners as banner, i}
                <div
                    class="absolute inset-0 transition-opacity duration-1000 {i === currentIndex ? 'opacity-100' : 'opacity-0'}"
                >
                    {#if banner.link}
                        <a href={banner.link} class="block w-full h-full" onclick={onLinkClick}>
                            <img src={banner.image_url} alt={banner.title} class="w-full h-full object-cover" draggable="false" />
                        </a>
                    {:else}
                        <img src={banner.image_url} alt={banner.title} class="w-full h-full object-cover" draggable="false" />
                    {/if}
                </div>
            {/each}

            {#if banners.length > 1}
                <!-- 인디케이터 dots -->
                <div class="absolute bottom-6 left-1/2 -translate-x-1/2 flex gap-2 z-10">
                    {#each banners as _, i}
                        <button
                            aria-label="{i + 1}번 슬라이드로 이동"
                            onclick={() => goTo(i)}
                            class="w-2.5 h-2.5 rounded-full transition-all duration-300 {i === currentIndex ? 'bg-white scale-125' : 'bg-white/50 hover:bg-white/75'}"
                        ></button>
                    {/each}
                </div>
            {/if}
        {/if}
    </div>
</section>

<!-- 2. 교회 소개 (Quick Links for About) -->
<section class="py-12 md:py-24 bg-white">
    <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12">
        <div class="text-center mb-10 md:mb-16">
            <h2
                class="text-2xl md:text-4xl font-bold text-gray-900 tracking-tight"
            >
                교회 소개
            </h2>
            <p class="mt-3 text-base md:text-xl text-gray-500">
                부평동부교회를 안내해 드립니다
            </p>
        </div>
        <div class="grid grid-cols-3 md:grid-cols-3 lg:grid-cols-6 gap-3 md:gap-6">
            {#each [{ name: "비전", icon: "M13 10V3L4 14h7v7l9-11h-7z", href: "/about?tab=vision" }, { name: "연혁", icon: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z", href: "/about?tab=history" }, { name: "담임목사", icon: "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z", href: "/about?tab=pastor" }, { name: "섬기는 사람들", icon: "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z", href: "/about?tab=people" }, { name: "예배 안내", icon: "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253", href: "/about?tab=worship" }, { name: "오시는 길", icon: "M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z M15 11a3 3 0 11-6 0 3 3 0 016 0z", href: "/about?tab=map" }] as item}
                <a
                    href={item.href}
                    class="flex flex-col items-center p-4 sm:p-6 md:p-8 bg-gray-50 rounded-2xl hover:bg-primary-50 hover:border-primary-200 border border-gray-100 transition-all hover:-translate-y-1"
                >
                    <svg
                        class="w-7 h-7 sm:w-8 sm:h-8 md:w-10 md:h-10 text-primary-500 mb-2 md:mb-4"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                        ><path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="1.5"
                            d={item.icon}
                        /></svg
                    >
                    <span class="text-xs sm:text-sm md:text-lg font-bold text-gray-900 text-center"
                        >{item.name}</span
                    >
                </a>
            {/each}
        </div>
    </div>
</section>

<!-- 3. 영상 (설교, 실황, 찬양) -->
<section class="py-12 md:py-24 bg-background">
    <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12">
        <div class="flex flex-col md:flex-row md:justify-between md:items-end mb-8 md:mb-12">
            <div>
                <h2
                    class="text-2xl md:text-4xl font-bold text-gray-900 tracking-tight"
                >
                    은혜의 영상
                </h2>
                <p class="mt-2 md:mt-4 text-base md:text-xl text-gray-500">
                    예배 실황, 설교, 찬양 다시보기
                </p>
            </div>
            <a
                href="/videos"
                class="mt-3 md:mt-0 self-start md:self-auto text-base md:text-lg font-bold text-primary-600 hover:text-primary-700 transition-colors flex items-center"
            >
                영상 전체보기 <svg
                    class="ml-1.5 w-4 h-4 md:ml-2 md:w-5 md:h-5"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    ><path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 5l7 7-7 7"
                    ></path></svg
                >
            </a>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-10">
            {#each videos as video}
                <a
                    href={video.youtubeUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="group flex flex-col bg-white rounded-3xl overflow-hidden shadow-sm hover:shadow-2xl transition-all duration-300 border border-gray-100"
                >
                    <div class="relative aspect-video overflow-hidden">
                        <img
                            src={video.thumbnail}
                            alt={video.title}
                            class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                            onerror={(e) => {
                                const img = e.currentTarget as HTMLImageElement;
                                if (img.src.includes('maxresdefault')) {
                                    img.src = img.src.replace('maxresdefault', 'hqdefault');
                                } else if (img.src.includes('hqdefault')) {
                                    img.src = img.src.replace('hqdefault', 'mqdefault');
                                } else if (img.src.includes('mqdefault')) {
                                    img.src = img.src.replace('mqdefault', 'default');
                                } else {
                                    img.style.display = 'none';
                                    const fallback = img.parentElement?.querySelector('.thumb-fallback') as HTMLElement;
                                    if (fallback) fallback.style.display = 'flex';
                                }
                            }}
                        />
                        <div class="thumb-fallback w-full h-full bg-gray-200 flex items-center justify-center absolute inset-0" style="display:none">
                            <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
                        </div>
                        <div
                            class="absolute inset-0 bg-black/20 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center"
                        >
                            <div
                                class="w-16 h-16 bg-white/95 rounded-full flex items-center justify-center backdrop-blur-sm shadow-xl"
                            >
                                <svg
                                    class="w-8 h-8 text-primary-900 ml-1"
                                    fill="currentColor"
                                    viewBox="0 0 24 24"
                                    ><path d="M8 5v14l11-7z" /></svg
                                >
                            </div>
                        </div>
                    </div>
                    <div class="p-5 md:p-8">
                        <div
                            class="flex items-center text-sm font-bold text-primary-500 mb-3 tracking-wide"
                        >
                            {video.category}
                            <span class="mx-3 text-gray-300">|</span>
                            <span class="text-gray-500">{video.date}</span>
                        </div>
                        <h3
                            class="text-lg md:text-2xl font-bold text-gray-900 leading-snug group-hover:text-primary-600 transition-colors"
                        >
                            {video.title}
                        </h3>
                    </div>
                </a>
            {/each}
        </div>
    </div>
</section>

<!-- 4 & 5. 게시판 섹션 (교회 소식 & 일반 게시판) -->
<section class="py-12 md:py-24 bg-white">
    <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-16">
            <!-- 교회 소식 -->
            <div>
                <div
                    class="flex justify-between items-center mb-8 border-b-2 border-gray-900 pb-4"
                >
                    <h2 class="text-2xl md:text-3xl font-bold text-gray-900">교회 소식</h2>
                    <a
                        href="/news"
                        class="text-lg font-bold text-gray-500 hover:text-primary-600 transition-colors"
                        >더보기 +</a
                    >
                </div>
                <ul class="divide-y divide-gray-100">
                    {#each latestNews as news}
                        <li>
                            <a
                                href={`/news/${news.id}`}
                                class="flex items-center justify-between py-5 group"
                            >
                                <div
                                    class="flex items-center gap-4 overflow-hidden"
                                >
                                    <span
                                        class="shrink-0 px-3 py-1 bg-primary-50 text-primary-700 text-sm font-bold rounded-lg"
                                        >{news.category}</span
                                    >
                                    <span
                                        class="text-sm md:text-xl font-medium text-gray-800 truncate group-hover:text-primary-600 transition-colors"
                                        >{news.title}</span
                                    >
                                </div>
                                <span
                                    class="shrink-0 text-xs md:text-base text-gray-400 font-medium ml-2 md:ml-4"
                                    >{news.date}</span
                                >
                            </a>
                        </li>
                    {/each}
                </ul>
            </div>

            <!-- 일반 게시판 -->
            <div>
                <div
                    class="flex justify-between items-center mb-8 border-b-2 border-gray-900 pb-4"
                >
                    <h2 class="text-2xl md:text-3xl font-bold text-gray-900">
                        일반 게시판
                    </h2>
                    <a
                        href="/board"
                        class="text-lg font-bold text-gray-500 hover:text-primary-600 transition-colors"
                        >더보기 +</a
                    >
                </div>
                <ul class="divide-y divide-gray-100">
                    {#each latestBoard as post}
                        <li>
                            <a
                                href={`/board/${post.id}`}
                                class="flex items-center justify-between py-5 group"
                            >
                                <div
                                    class="flex items-center gap-4 overflow-hidden"
                                >
                                    <span
                                        class="text-sm md:text-xl font-medium text-gray-800 truncate group-hover:text-primary-600 transition-colors"
                                        >{post.title}</span
                                    >
                                </div>
                                <div
                                    class="shrink-0 flex items-center gap-2 md:gap-4 ml-2 md:ml-4"
                                >
                                    <span class="hidden sm:block text-sm md:text-base text-gray-500"
                                        >{post.author}</span
                                    >
                                    <span
                                        class="text-xs md:text-base text-gray-400 font-medium"
                                        >{post.date}</span
                                    >
                                </div>
                            </a>
                        </li>
                    {/each}
                </ul>
            </div>
        </div>
    </div>
</section>

<!-- Social Links -->
<section class="py-10 md:py-16 bg-gray-50">
    <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12">
        <div class="flex flex-col sm:flex-row justify-center items-center gap-4">
            <a
                href="https://www.youtube.com/@dbchurch"
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-3 px-8 py-4 bg-red-600 hover:bg-red-700 text-white font-bold text-lg rounded-2xl transition-all hover:-translate-y-0.5 shadow-sm hover:shadow-lg w-full sm:w-auto justify-center"
            >
                <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
                </svg>
                Youtube
            </a>
            <a
                href={appLink}
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-3 px-8 py-4 bg-gray-900 hover:bg-gray-800 text-white font-bold text-lg rounded-2xl transition-all hover:-translate-y-0.5 shadow-sm hover:shadow-lg w-full sm:w-auto justify-center"
            >
                {#if isApplePlatform}
                    <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.7 9.05 7.4c1.39.07 2.35.74 3.18.76 1.22-.21 2.38-.91 3.69-.82 1.57.12 2.75.76 3.51 1.92-3.22 1.93-2.46 6.16.62 7.5-.64 1.64-1.48 3.26-3 3.52zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
                    </svg>
                {:else}
                    <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M3.18 23.76c.3.17.64.24.99.2l12.23-12.24L13.23 8.6 3.18 23.76zm17.29-11.53c.52-.3.83-.84.83-1.44s-.31-1.14-.83-1.44l-2.43-1.4-3.12 3.12 3.12 3.12 2.43-1.4zM.42 1.04C.16 1.36 0 1.8 0 2.33v19.34c0 .53.16.97.42 1.29l.07.07 10.83-10.84v-.25L.49.97.42 1.04zm12.81 11.5L3 22.77l.07.07c.3.17.64.24.99.2l12.23-12.24-3.06-3.06z"/>
                    </svg>
                {/if}
                App 설치
            </a>
            <a
                href="https://www.instagram.com/bpdbchurch"
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-3 px-8 py-4 bg-linear-to-r from-purple-500 via-pink-500 to-orange-400 hover:opacity-90 text-white font-bold text-lg rounded-2xl transition-all hover:-translate-y-0.5 shadow-sm hover:shadow-lg w-full sm:w-auto justify-center"
            >
                <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z"/>
                </svg>
                Instagram
            </a>
        </div>
    </div>
</section>
