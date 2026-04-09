<script lang="ts">
    import { fade } from "svelte/transition";
    import { page } from "$app/stores";

    const subMenus = [
        { name: "영아부", id: "infant" },
        { name: "유치부", id: "preschool" },
        { name: "유초등부", id: "elementary" },
        { name: "중고등부", id: "youth" },
        { name: "청년부", id: "young-adult" },
    ];
    let activeTab = $state("infant");

    $effect(() => {
        const tab = $page.url.searchParams.get("tab");
        if (tab && subMenus.some((m) => m.id === tab)) {
            activeTab = tab;
        }
    });
</script>

<!-- Header Section -->
<div class="bg-gradient-to-b from-primary-50 to-white py-5 md:py-15 border-b border-gray-100">
    <div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 text-center animate-fade-in-up">
        <h1 class="text-3xl md:text-6xl font-black text-gray-900 mb-4 md:mb-8 tracking-tight font-serif drop-shadow-sm">
            다음 세대
        </h1>
        <p class="text-base md:text-2xl text-gray-600 max-w-3xl mx-auto font-light leading-relaxed">
            미래를 이끌어 갈 다음 세대를,<br class="hidden md:block" />
            말씀과 사랑으로 <strong class="font-bold text-primary-700">세워가는 사역</strong>
        </p>
    </div>
</div>

<div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 md:py-5">
    <!-- Sub Navigation - Mobile: Select dropdown -->
    <div class="md:hidden mb-8">
        <select
            bind:value={activeTab}
            class="w-full px-4 py-3.5 rounded-2xl border-2 border-gray-200 bg-white font-bold text-gray-800 text-base focus:outline-none focus:border-primary-500 transition-colors"
        >
            {#each subMenus as menu}
                <option value={menu.id}>{menu.name}</option>
            {/each}
        </select>
    </div>

    <!-- Sub Navigation - Desktop: Tab buttons -->
    <div class="hidden md:flex border-b-2 border-gray-100 mb-20 justify-center">
        {#each subMenus as menu}
            <button
                type="button"
                class="whitespace-nowrap py-4 px-8 lg:px-12 border-b-4 font-bold text-lg lg:text-xl transition-all duration-300 {activeTab ===
                menu.id
                    ? 'border-primary-600 text-primary-700'
                    : 'border-transparent text-gray-400 hover:text-gray-800 hover:border-gray-300'}"
                onclick={() => (activeTab = menu.id)}
            >
                {menu.name}
            </button>
        {/each}
    </div>

    <!-- Content Area -->
    <div class="max-w-6xl mx-auto min-h-[60vh]">

        <!-- 영아부 -->
        {#if activeTab === "infant"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">👶</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">영아부</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            갓 태어난 아기부터 36개월 영아를 대상으로 하는 부서입니다.
                            부모와 함께 하나님의 사랑을 느끼고, 따뜻한 신앙의 첫 발걸음을 내딛을 수 있도록 돕습니다.
                        </p>
                    </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">대상</h3>
                        <p class="text-gray-600 font-medium">출생 ~ 36개월</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">예배 시간</h3>
                        <p class="text-gray-600 font-medium">주일 오전 11시</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">장소</h3>
                        <p class="text-gray-600 font-medium">로뎀나무숲</p>
                    </div>
                </div>
            </div>
        {/if}

        <!-- 유치부 -->
        {#if activeTab === "preschool"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">🧒</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">유치부</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            4~7세 유아들이 찬양과 말씀, 놀이를 통해 하나님을 만나는 부서입니다.
                            눈높이에 맞는 예배와 교육으로 어린 마음에 믿음의 씨앗을 심어갑니다.
                        </p>
                    </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">대상</h3>
                        <p class="text-gray-600 font-medium">4세 ~ 7세 (미취학)</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">예배 시간</h3>
                        <p class="text-gray-600 font-medium">주일 오전 11시</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">주요 활동</h3>
                        <p class="text-gray-600 font-medium">찬양 · 성경 이야기 · 만들기</p>
                    </div>
                </div>
            </div>
        {/if}

        <!-- 유초등부 -->
        {#if activeTab === "elementary"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">📚</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">유초등부</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            초등학교 1~6학년 어린이들이 말씀을 배우고 믿음을 키워가는 부서입니다.
                            성경 교육과 다양한 활동을 통해 기독교 세계관을 갖춘 하나님의 어린이로 자라도록 이끌어 갑니다.
                        </p>
                    </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">대상</h3>
                        <p class="text-gray-600 font-medium">초등학교 1 ~ 6학년</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">예배 시간</h3>
                        <p class="text-gray-600 font-medium">주일 오전 11시</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">주요 활동</h3>
                        <p class="text-gray-600 font-medium">성경 암송 · 소그룹 · 캠프</p>
                    </div>
                </div>
            </div>
        {/if}

        <!-- 중고등부 -->
        {#if activeTab === "youth"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">🎒</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">중고등부</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            중학교 1학년부터 고등학교 3학년 청소년들이 함께하는 부서입니다.
                            말씀과 예배, 또래 관계 속에서 흔들리지 않는 믿음의 정체성을 세워나갑니다.
                        </p>
                    </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">대상</h3>
                        <p class="text-gray-600 font-medium">중학교 1학년 ~ 고등학교 3학년</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">예배 시간</h3>
                        <p class="text-gray-600 font-medium">주일 오후 1시 30분</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">주요 활동</h3>
                        <p class="text-gray-600 font-medium">수련회 · 큐티 · 소그룹 모임</p>
                    </div>
                </div>
            </div>
        {/if}

        <!-- 청년부 -->
        {#if activeTab === "young-adult"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">🙌</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">청년부</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            대학생부터 청년들이 함께 모여 예배하고 삶을 나누는 부서입니다.
                            세상 속에서 그리스도인으로 살아가는 방법을 함께 고민하고,
                            하나님나라를 향한 비전을 품고 세상으로 나아갑니다.
                        </p>
                    </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">대상</h3>
                        <p class="text-gray-600 font-medium">대학생 · 청년 (19세 이상)</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">예배 시간</h3>
                        <p class="text-gray-600 font-medium">주일 오후 2시</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">주요 활동</h3>
                        <p class="text-gray-600 font-medium">셀 모임 · 성경 스터디 · 봉사</p>
                    </div>
                </div>
            </div>
        {/if}

    </div>
</div>
