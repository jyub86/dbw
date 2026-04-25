<script lang="ts">
    import { fade } from "svelte/transition";
    import { page } from "$app/stores";

    const subMenus = [
        { name: "열매공동체", id: "yeolmae" },
        { name: "줄기공동체", id: "julgi" },
        { name: "뿌리공동체", id: "ppuri" },
        { name: "새가족부", id: "newmember" },
        { name: "로뎀나무숲", id: "rodem" },
    ];
    let activeTab = $state("yeolmae");

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
            공동체
        </h1>
        <p class="text-base md:text-2xl text-gray-600 max-w-3xl mx-auto font-light leading-relaxed">
            함께 모여 말씀을 나누고,<br class="hidden md:block" />
            삶을 <strong class="font-bold text-primary-700">함께 걸어가는 신앙공동체</strong>
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

        <!-- 열매공동체 -->
        {#if activeTab === "yeolmae"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <!-- 소개 카드 -->
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">🍎</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">열매공동체</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            31-55세 성도들이 함께하는 공동체입니다. 활발한 교제와 역동적인 사역 속에서
                            믿음의 열매를 맺으며, 하나님나라를 향해 함께 나아갑니다.
                        </p>
                    </div>
                </div>

                <!-- 정보 카드 3개 -->
                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">모임 대상</h3>
                        <p class="text-gray-600 font-medium">31-55세 성도</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">모임 시간</h3>
                        <p class="text-gray-600 font-medium">주일 오후 1시 30분</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">주요 사역</h3>
                        <p class="text-gray-600 font-medium">소그룹 성경공부 · 교제</p>
                    </div>
                </div>
            </div>
        {/if}

        <!-- 줄기공동체 -->
        {#if activeTab === "julgi"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">🌿</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">줄기공동체</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            56-70세 성도들이 함께하는 공동체입니다. 풍성한 신앙의 경험을 나누며
                            교회의 든든한 줄기가 되어 다음세대와 어르신 사이를 이어주는 중추 공동체입니다.
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
                        <h3 class="font-black text-gray-900 text-lg mb-2">모임 대상</h3>
                        <p class="text-gray-600 font-medium">56-70세 성도</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">모임 시간</h3>
                        <p class="text-gray-600 font-medium">주일 오후 1시 30분</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">주요 사역</h3>
                        <p class="text-gray-600 font-medium">소그룹 성경공부 · 교제</p>
                    </div>
                </div>
            </div>
        {/if}

        <!-- 뿌리공동체 -->
        {#if activeTab === "ppuri"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">🌱</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">뿌리공동체</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            71세 이상 어르신 성도들이 함께하는 공동체입니다. 오랜 믿음의 여정 속에 쌓아온
                            신앙의 유산을 나누며, 교회의 깊은 뿌리로서 기도와 사랑으로 공동체를 지탱합니다.
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
                        <h3 class="font-black text-gray-900 text-lg mb-2">모임 대상</h3>
                        <p class="text-gray-600 font-medium">71세 이상 성도</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">모임 시간</h3>
                        <p class="text-gray-600 font-medium">주일 오후 1시 30분</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">주요 사역</h3>
                        <p class="text-gray-600 font-medium">소그룹 성경공부 · 교제</p>
                    </div>
                </div>
            </div>
        {/if}

        <!-- 새가족부 -->
        {#if activeTab === "newmember"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">🤝</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">새가족부</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            처음 부평동부교회를 찾아오신 분들을 따뜻하게 맞이하는 부서입니다.
                            새가족 교육과 소그룹 모임을 통해 교회 공동체에 자연스럽게 정착하도록 돕습니다.
                        </p>
                    </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">모임 대상</h3>
                        <p class="text-gray-600 font-medium">처음 방문하신 모든 분</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">새가족 교육</h3>
                        <p class="text-gray-600 font-medium">주일 2부 예배 후</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">문의</h3>
                        <p class="text-gray-600 font-medium">032-515-1401</p>
                    </div>
                </div>
            </div>
        {/if}

        <!-- 로뎀나무숲 -->
        {#if activeTab === "rodem"}
            <div class="space-y-12" in:fade={{ duration: 400 }}>
                <div class="bg-white rounded-4xl p-8 md:p-16 shadow-xl shadow-primary-900/5 border border-primary-50 relative overflow-hidden">
                    <div class="absolute top-0 right-0 w-64 h-64 bg-primary-50 rounded-full -translate-y-1/2 translate-x-1/2 opacity-50"></div>
                    <div class="relative">
                        <p class="text-5xl mb-6">🌳</p>
                        <h2 class="text-3xl md:text-4xl font-black text-gray-900 mb-4">로뎀나무숲</h2>
                        <p class="text-lg md:text-xl text-gray-600 leading-relaxed max-w-2xl">
                            부모님이 예배에 집중할 수 있도록 영·유아 자녀를 전문적으로 돌봐주는 시설입니다.
                            안전하고 사랑이 넘치는 환경 속에서 아이들이 편안하게 지낼 수 있도록 정성껏 섬깁니다.
                        </p>
                    </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">이용 대상</h3>
                        <p class="text-gray-600 font-medium">영·유아 자녀를 둔 가정</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">운영 시간</h3>
                        <p class="text-gray-600 font-medium">주일 예배 시간 & 소그룹 모임 시간 운영</p>
                    </div>
                    <div class="bg-white rounded-3xl p-8 shadow-md border border-gray-100 text-center">
                        <div class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
                            <svg class="w-7 h-7 text-primary-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                        </div>
                        <h3 class="font-black text-gray-900 text-lg mb-2">위치</h3>
                        <p class="text-gray-600 font-medium">교회 1층 로뎀나무숲</p>
                    </div>
                </div>
            </div>
        {/if}

    </div>
</div>
