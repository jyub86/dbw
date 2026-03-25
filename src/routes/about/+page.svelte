<script lang="ts">
    import { fade, slide } from "svelte/transition";
    import { page } from "$app/stores";
    import type { PageData } from "./$types";

    let { data }: { data: PageData } = $props();

    const subMenus = [
        { name: "비전 및 사역", id: "vision" },
        { name: "교회 연혁", id: "history" },
        { name: "담임목사 소개", id: "pastor" },
        { name: "섬기는 분들", id: "people" },
        { name: "예배 안내", id: "worship" },
        { name: "오시는 길", id: "map" },
    ];
    let activeTab = $state("vision");

    // URL 쿼리 파라미터에서 tab 값을 읽어와 활성 탭으로 설정
    $effect(() => {
        const tab = $page.url.searchParams.get("tab");
        if (tab && subMenus.some((m) => m.id === tab)) {
            activeTab = tab;
        }
    });

    const coreMinistries = [
        {
            num: "1",
            title: "예배",
            subtitle: "하나님의 교회 · 하나님나라의 실존을 알림",
            desc: "찬양과 말씀의 양 날개로 비상하며 살아있는 예배를 드린다.",
            details: [
                "순전한 찬양으로 하나님의 임재와 영광을 체험한다.",
                "온전한 말씀의 선포를 통해 치유와 회복을 경험한다.",
                "감동과 결단으로 세상에 대하여 소망을 품고 나아간다.",
            ],
            icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"></path></svg>`,
        },
        {
            num: "2",
            title: "교육",
            subtitle: "하나님의 교회 · 하나님나라의 실존을 알림",
            desc: "지정의, 전인격적 접근으로 세상과 차별화된 교육을 추구한다.",
            details: [
                "기독교 세계관의 정립으로 사회를 변화시킬 인재를 양성한다.",
                "인격적 교감을 바탕으로 내일의 주역들이 삶의 목적을 찾게 한다.",
                "행동하는 신앙인으로서 민족과 세계를 가슴에 품고 나아가게 한다.",
            ],
            icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"></path></svg>`,
        },
        {
            num: "3",
            title: "선교",
            subtitle: "예수님의 교회 · 하나님나라의 완성에 동참함",
            desc: "선교적 교회로서 세계선교와 국내선교에 적극적으로 동참한다.",
            details: [
                "그리스도를 필요로 하는 누구에게나 복음을 들고 찾아가 소개한다.",
                "선교 현장과의 긴밀한 협력을 통해 효과적인 선교사역을 시행한다.",
                "복음전도의 사명은 하나님나라가 도래하기까지 성실하게 감당한다.",
            ],
            icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>`,
        },
        {
            num: "4",
            title: "봉사",
            subtitle: "예수님의 교회 · 하나님나라의 완성에 동참함",
            desc: "예수께서 가르쳐주신 이웃사랑으로 아름다운 세상을 만들어 간다.",
            details: [
                "소외된 이웃을 돌아보고 지역주민들과 슬픔과 기쁨을 함께 한다.",
                "교회가 이웃의 필요가 되어 더불어 사는 세상 만들기에 앞장선다.",
                "건전한 문화, 복지의 창출을 통해 건강한 사회를 선도해 나간다.",
            ],
            icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"></path></svg>`,
        },
        {
            num: "5",
            title: "교제",
            subtitle: "성령님의 교회 · 하나님나라의 삶을 선험함",
            desc: "성령 충만한 공동체로서 모든 벽을 허물고 가족의 삶을 경험한다.",
            details: [
                "세대 간 격차를 뛰어 넘어 서로 사랑하며 존중하는 삶을 연습한다.",
                "갈등과 충돌 속에서도 용서와 화해, 그리고 사랑을 배운다.",
                "집단이기주의를 극복하고 모두를 품어 참된 행복을 창출한다.",
            ],
            icon: `<svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path></svg>`,
        },
    ];

    const historyData = $derived(data.historyData);

    const peopleData = [
        {
            name: "강길수",
            role: "담임목사",
            duty: "",
            phone: "032-515-1401",
        },
        {
            name: "이동호",
            role: "부목사",
            duty: "행정 / 청년부",
            phone: "032-503-9211",
        },
        {
            name: "김현겸",
            role: "부목사",
            duty: "사랑공동체 / 3040 / 중고등부 / 찬양단",
            phone: "032-503-9214",
        },
        {
            name: "임효빈",
            role: "부목사",
            duty: "화평공동체 / 유초등부 / 전도폭발 / 지역전도",
            phone: "032-513-7975",
        },
        {
            name: "한성숙",
            role: "전임전도사",
            duty: "교구",
            phone: "032-503-9212",
        },
        { name: "유선아", role: "교육전도사", duty: "유치부", phone: "" },
        { name: "최사라", role: "교육전도사", duty: "영아부", phone: "" },
        {
            name: "이명애",
            role: "시무간사",
            duty: "교회재정 / 사무",
            phone: "032-515-1401",
        },
        {
            name: "구제만",
            role: "교회관리",
            duty: "교회관리",
            phone: "032-522-7318",
        },
    ];
</script>

<svelte:head>
    <title>교회 소개 - 부평동부교회</title>
</svelte:head>

<!-- Header Section -->
<div
    class="bg-gradient-to-b from-primary-50 to-white py-14 md:py-36 border-b border-gray-100"
>
    <div
        class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 text-center animate-fade-in-up"
    >
        <h1
            class="text-3xl md:text-6xl font-black text-gray-900 mb-4 md:mb-8 tracking-tight font-serif drop-shadow-sm"
        >
            교회 소개
        </h1>
        <p
            class="text-base md:text-2xl text-gray-600 max-w-3xl mx-auto font-light leading-relaxed"
        >
            하나님의 사랑으로 세상을 품고,<br class="hidden md:block" />
            말씀과 기도로
            <strong class="font-bold text-gray-900 text-primary-700"
                >하나님나라를 세워가는 신앙공동체</strong
            >
        </p>
    </div>
</div>

<div class="max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 md:py-24">
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
    <div
        class="hidden md:flex border-b-2 border-gray-100 mb-20 justify-center"
    >
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
        {#if activeTab === "vision"}
            <div
                class="animate-fade-in-up space-y-16 md:space-y-32"
                in:fade={{ duration: 400 }}
            >
                <!-- 표어 섹션 -->
                <div
                    class="text-center bg-white rounded-4xl md:rounded-[3rem] p-8 md:p-24 shadow-xl shadow-primary-900/5 relative overflow-hidden border border-primary-50"
                >
                    <div
                        class="absolute inset-0 bg-gradient-to-br from-primary-50/50 via-white to-white opacity-80"
                    ></div>
                    <div class="relative z-10">
                        <span
                            class="inline-block py-2 px-6 rounded-full bg-primary-100 text-primary-700 font-bold tracking-widest text-sm mb-8"
                            >영구 표어</span
                        >
                        <h2
                            class="text-3xl md:text-5xl lg:text-7xl font-black text-gray-900 mb-8 md:mb-16 font-serif leading-tight"
                        >
                            하나님나라 이루어가는 <br />신앙공동체
                        </h2>

                        <div
                            class="max-w-4xl mx-auto bg-white p-6 md:p-12 rounded-3xl mb-8 md:mb-12 shadow-md border border-gray-100 transform hover:-translate-y-1 transition-transform duration-500"
                        >
                            <span
                                class="text-primary-600 font-bold mb-3 block tracking-wider text-sm md:text-base"
                                >2026년 주제 표어</span
                            >
                            <p
                                class="text-xl md:text-4xl font-bold text-gray-900 mb-4 md:mb-6 leading-relaxed"
                            >
                                "소그룹과 함께 마음을 같이하는 교회"
                            </p>
                            <p class="text-xl text-gray-500 italic font-serif">
                                (사도행전 2:46)
                            </p>
                        </div>

                        <div
                            class="grid grid-cols-1 md:grid-cols-3 gap-8 mt-20 text-center border-t border-gray-100 pt-16"
                        >
                            <div
                                class="space-y-4 p-6 rounded-2xl hover:bg-gray-50 transition-colors"
                            >
                                <h4 class="text-xl font-bold text-primary-700">
                                    성부 하나님의 교회
                                </h4>
                                <p
                                    class="text-gray-600 text-lg leading-relaxed"
                                >
                                    하나님나라의 실존을 알리는 공동체
                                </p>
                            </div>
                            <div
                                class="space-y-4 p-6 rounded-2xl hover:bg-gray-50 transition-colors border-y md:border-y-0 md:border-x border-gray-100"
                            >
                                <h4 class="text-xl font-bold text-primary-700">
                                    성자 하나님의 교회
                                </h4>
                                <p
                                    class="text-gray-600 text-lg leading-relaxed"
                                >
                                    하나님나라의 완성에 동참하는 공동체
                                </p>
                            </div>
                            <div
                                class="space-y-4 p-6 rounded-2xl hover:bg-gray-50 transition-colors"
                            >
                                <h4 class="text-xl font-bold text-primary-700">
                                    성령 하나님의 교회
                                </h4>
                                <p
                                    class="text-gray-600 text-lg leading-relaxed"
                                >
                                    하나님나라의 삶을 선험하는 공동체
                                </p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- 5대 핵심 사역 -->
                <div>
                    <div class="text-center mb-16">
                        <span
                            class="text-primary-600 font-bold tracking-widest uppercase mb-4 block"
                            >Core Ministries</span
                        >
                        <h3
                            class="text-4xl md:text-5xl font-black text-gray-900 font-serif"
                        >
                            5대 영구 핵심 사역
                        </h3>
                    </div>

                    <div class="grid grid-cols-1 gap-10">
                        {#each coreMinistries as min, index}
                            <div
                                class="bg-white rounded-[2.5rem] p-6 md:p-16 shadow-lg shadow-gray-200/50 border border-gray-100 hover:shadow-xl hover:border-primary-100 transition-all duration-300 group flex flex-col md:flex-row gap-6 md:gap-16 items-start"
                            >
                                <!-- 아이콘 및 제목 영역 -->
                                <div class="w-full md:w-1/3 shrink-0">
                                    <div
                                        class="w-20 h-20 rounded-[1.5rem] bg-primary-50 text-primary-600 flex items-center justify-center mb-8 group-hover:scale-110 group-hover:bg-primary-600 group-hover:text-white transition-all duration-500 shadow-sm"
                                    >
                                        {@html min.icon}
                                    </div>
                                    <span
                                        class="text-sm font-bold text-primary-500 tracking-wide mb-3 block"
                                        >{min.subtitle}</span
                                    >
                                    <h4
                                        class="text-2xl md:text-4xl font-black text-gray-900 flex items-center gap-4 mb-4"
                                    >
                                        {min.title}
                                        <span
                                            class="text-gray-200 font-serif text-5xl leading-none"
                                            >0{min.num}</span
                                        >
                                    </h4>
                                    <p
                                        class="text-base md:text-xl text-gray-700 font-bold leading-relaxed break-keep"
                                    >
                                        "{min.desc}"
                                    </p>
                                </div>

                                <!-- 상세 설명 영역 -->
                                <div
                                    class="w-full md:w-2/3 border-t md:border-t-0 md:border-l border-gray-100 pt-8 md:pt-0 md:pl-16"
                                >
                                    <ul class="space-y-6">
                                        {#each min.details as detail}
                                            <li class="flex items-start gap-4">
                                                <div
                                                    class="mt-2.5 w-2 h-2 rounded-full bg-primary-400 shrink-0"
                                                ></div>
                                                <p
                                                    class="text-base md:text-xl text-gray-600 leading-relaxed break-keep font-medium"
                                                >
                                                    {detail}
                                                </p>
                                            </li>
                                        {/each}
                                    </ul>
                                </div>
                            </div>
                        {/each}
                    </div>
                </div>
            </div>
        {/if}

        {#if activeTab === "history"}
            <div class="animate-fade-in-up" in:fade={{ duration: 400 }}>
                <div class="text-center mb-16">
                    <span
                        class="text-primary-600 font-bold tracking-widest uppercase mb-4 block"
                        >Our Journey</span
                    >
                    <h2
                        class="text-4xl md:text-5xl font-black text-gray-900 font-serif mb-6"
                    >
                        교회의 주요 발자취
                    </h2>
                    <p class="text-xl text-gray-600 max-w-2xl mx-auto">
                        1980년 개척부터 현재까지, 은혜로 걸어온 부평동부교회의
                        역사입니다.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    {#each historyData as period}
                        <div class="mb-20">
                            <!-- 연대 제목 -->
                            <h3
                                class="text-3xl font-black text-primary-700 mb-10 pb-4 flex items-center gap-4"
                            >
                                <span
                                    class="w-3 h-10 bg-primary-600 rounded-full inline-block"
                                ></span>
                                {period.decade}
                            </h3>

                            <!-- 타임라인 컨테이너 (좌측 수직선) -->
                            <div
                                class="space-y-10 relative border-l-2 border-primary-100 ml-1.5 md:ml-[12rem] py-6"
                            >
                                {#each period.events as event}
                                    <div
                                        class="flex flex-col md:flex-row md:items-start gap-2 md:gap-0 group relative pl-8 md:pl-16"
                                    >
                                        <!-- 타임라인 노드 (점) -->
                                        <div
                                            class="absolute -left-2 top-3 w-3.5 h-3.5 rounded-full bg-white group-hover:bg-primary-500 group-hover:scale-150 group-hover:border-transparent transition-all duration-300 border-[3px] border-gray-900 ring-4 ring-white"
                                        ></div>

                                        <!-- 년/월/일 (데스크탑: 선 좌측 배치 / 모바일: 본문 위) -->
                                        <div
                                            class="md:absolute md:-left-[12.5rem] md:w-40 md:text-right shrink-0 pt-0.5"
                                        >
                                            <span
                                                class="text-xl md:text-2xl font-bold text-gray-400 group-hover:text-primary-600 transition-colors duration-300 font-mono tracking-tight"
                                                >{event.date}</span
                                            >
                                        </div>

                                        <!-- 설명 -->
                                        <div
                                            class="flex-1 pb-10 border-b border-gray-100"
                                        >
                                            <p
                                                class="text-xl md:text-2xl text-gray-800 font-medium leading-relaxed group-hover:text-gray-900 break-keep"
                                            >
                                                {event.desc}
                                            </p>
                                        </div>
                                    </div>
                                {/each}
                            </div>
                        </div>
                    {/each}
                </div>
            </div>
        {/if}

        {#if activeTab === "pastor"}
            <div class="animate-fade-in-up" in:fade={{ duration: 400 }}>

                <!-- 헤더 배너 -->
                <div class="relative bg-linear-to-br from-primary-900 via-primary-800 to-primary-700 rounded-[3rem] overflow-hidden mb-16 shadow-2xl">
                    <!-- 장식 원형 -->
                    <div class="absolute -left-24 -top-24 w-80 h-80 bg-white/5 rounded-full"></div>
                    <div class="absolute -right-16 -bottom-16 w-64 h-64 bg-white/5 rounded-full"></div>
                    <div class="absolute right-24 top-8 w-32 h-32 bg-primary-600/30 rounded-full blur-2xl"></div>

                    <div class="relative z-10 flex flex-col md:flex-row items-center gap-8 md:gap-16 p-8 md:p-16 lg:p-20">
                        <!-- 사진 -->
                        <div class="shrink-0">
                            <div class="w-48 h-48 md:w-64 md:h-64 rounded-4xl overflow-hidden shadow-2xl ring-4 ring-white/20">
                                <img
                                    src="https://images.unsplash.com/photo-1544256718-3baf24032d84?w=800"
                                    alt="강길수 담임목사"
                                    class="w-full h-full object-cover"
                                />
                            </div>
                        </div>

                        <!-- 이름/직책 -->
                        <div class="text-center md:text-left">
                            <span class="inline-block py-1.5 px-5 rounded-full bg-white/15 text-primary-100 font-bold tracking-widest text-sm mb-5">
                                제 4대 담임목사
                            </span>
                            <h2 class="text-4xl md:text-7xl font-black text-white font-serif mb-4 tracking-tight">
                                강길수
                            </h2>
                            <p class="text-xl md:text-2xl text-primary-200 font-medium mb-8">
                                부평동부교회 담임목사
                            </p>
                            <div class="flex flex-wrap justify-center md:justify-start gap-3">
                                <span class="py-2 px-5 rounded-full bg-white/10 text-white text-sm font-medium border border-white/20">대한예수교장로회 합동</span>
                                <span class="py-2 px-5 rounded-full bg-white/10 text-white text-sm font-medium border border-white/20">032-515-1401</span>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- 인용 문구 -->
                <div class="relative bg-primary-50 border border-primary-100 rounded-[2.5rem] p-10 md:p-14 mb-16 overflow-hidden">
                    <div class="absolute left-8 top-6 text-primary-200 text-[8rem] font-serif leading-none select-none">"</div>
                    <div class="relative z-10 text-center max-w-3xl mx-auto">
                        <p class="text-2xl md:text-3xl font-bold text-gray-900 leading-relaxed break-keep pt-6">
                            안녕하십니까?<br class="hidden md:block" />
                            부평동부교회를 섬기고 있는 강길수 목사입니다.
                        </p>
                        <p class="mt-6 text-lg text-primary-700 font-medium">
                            우리교회 홈페이지를 방문해주신 여러분을 진심으로 환영합니다.
                        </p>
                    </div>
                </div>

                <!-- 본문 인사말 -->
                <div class="bg-white rounded-[2.5rem] p-6 md:p-16 lg:p-20 shadow-xl border border-gray-100 mb-16 relative overflow-hidden">
                    <div class="absolute -right-20 -bottom-20 w-72 h-72 bg-primary-50/60 rounded-full blur-3xl pointer-events-none"></div>

                    <div class="relative z-10 space-y-0 divide-y divide-gray-100">

                        <!-- 단락 1 -->
                        <div class="flex flex-col md:flex-row gap-6 md:gap-12 py-10 first:pt-0 group">
                            <div class="shrink-0 md:w-36">
                                <span class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary-100 text-primary-700 group-hover:bg-primary-600 group-hover:text-white transition-all duration-300">
                                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-2 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/></svg>
                                </span>
                                <p class="mt-3 text-xs font-bold text-gray-400 tracking-widest uppercase hidden md:block">교회 소개</p>
                            </div>
                            <div class="flex-1">
                                <p class="text-lg md:text-xl text-gray-700 leading-loose break-keep">
                                    우리교회는 대한예수교장로회 합동 측 교단에 속한 교회로서 <strong class="text-gray-900">1964년 12월 18일</strong>, 우상렬 목사님과 몇 분의 성도들에 의해 이 땅에 모습을 드러내었습니다. 이후 우리교회는 수십 년이 흐르기까지 괄목할만한 성장을 이루며 부평의 중심교회로 자리매김을 해왔습니다. 한때 교회가 나누어지는 진통과 아픔을 겪기도 하였지만 지금은 오히려 치유하시는 하나님(여호와 라파)의 사랑의 손길을 깊이 경험하며 더욱 견고한 신앙공동체로 재도약을 하고 있습니다.
                                </p>
                            </div>
                        </div>

                        <!-- 단락 2 -->
                        <div class="flex flex-col md:flex-row gap-6 md:gap-12 py-10 group">
                            <div class="shrink-0 md:w-36">
                                <span class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary-100 text-primary-700 group-hover:bg-primary-600 group-hover:text-white transition-all duration-300">
                                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12l2 2 4-4M7.835 4.697a3.42 3.42 0 001.946-.806 3.42 3.42 0 014.438 0 3.42 3.42 0 001.946.806 3.42 3.42 0 013.138 3.138 3.42 3.42 0 00.806 1.946 3.42 3.42 0 010 4.438 3.42 3.42 0 00-.806 1.946 3.42 3.42 0 01-3.138 3.138 3.42 3.42 0 00-1.946.806 3.42 3.42 0 01-4.438 0 3.42 3.42 0 00-1.946-.806 3.42 3.42 0 01-3.138-3.138 3.42 3.42 0 00-.806-1.946 3.42 3.42 0 010-4.438 3.42 3.42 0 00.806-1.946 3.42 3.42 0 013.138-3.138z"/></svg>
                                </span>
                                <p class="mt-3 text-xs font-bold text-gray-400 tracking-widest uppercase hidden md:block">사명과 비전</p>
                            </div>
                            <div class="flex-1">
                                <p class="text-lg md:text-xl text-gray-700 leading-loose break-keep">
                                    저는 부평동부교회의 <strong class="text-gray-900">제 4대 목사</strong>로서 우리교회에 맡기신 하나님의 거룩한 사명을 이루기 위해 온 성도들과 함께 혼신의 힘을 기울이고 있습니다. 교회의 나아갈 방향과 목표 등은 교회비전에 자세하게 소개되어 있습니다. 우리교회는 그 내용을 따라 한걸음씩 성실하게 앞을 향하여 계속 나아갈 것입니다. 언젠가 다시 임할 주님의 나라를 소망하면서 이 땅에서 <strong class="text-primary-700">'영광스러운 교회'(엡 5:27)</strong>로서의 거룩한 자태를 선명하게 드러내기 위해 영성과 섬김과 사역의 고삐를 늦추지 않을 것입니다.
                                </p>
                            </div>
                        </div>

                        <!-- 단락 3 -->
                        <div class="flex flex-col md:flex-row gap-6 md:gap-12 py-10 group">
                            <div class="shrink-0 md:w-36">
                                <span class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary-100 text-primary-700 group-hover:bg-primary-600 group-hover:text-white transition-all duration-300">
                                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/></svg>
                                </span>
                                <p class="mt-3 text-xs font-bold text-gray-400 tracking-widest uppercase hidden md:block">홈페이지</p>
                            </div>
                            <div class="flex-1">
                                <p class="text-lg md:text-xl text-gray-700 leading-loose break-keep">
                                    우리교회의 홈페이지는 이러한 소망을 실현하는 데에 기여하고자 운영되고 있습니다. 모쪼록 방문하실 때마다 모든 분들이 주님을 섬기는 열정과 의욕이 생겨나고 세상을 변화시킬 주인공으로 강한 도전을 받으실 수 있기를 기대합니다. 특히 아직 예수 그리스도의 주되심을 고백하지 못하는 분들에게는 복음을 듣고 깨달아 우리와 동일한 신앙고백을 하실 수 있는 은혜가 임하기를 간절히 소망합니다.
                                </p>
                            </div>
                        </div>

                        <!-- 단락 4 -->
                        <div class="flex flex-col md:flex-row gap-6 md:gap-12 py-10 last:pb-0 group">
                            <div class="shrink-0 md:w-36">
                                <span class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-primary-100 text-primary-700 group-hover:bg-primary-600 group-hover:text-white transition-all duration-300">
                                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"/></svg>
                                </span>
                                <p class="mt-3 text-xs font-bold text-gray-400 tracking-widest uppercase hidden md:block">환영 인사</p>
                            </div>
                            <div class="flex-1">
                                <p class="text-lg md:text-xl text-gray-700 leading-loose break-keep">
                                    혹시, 홈페이지 방문중에 신앙의 상담을 원하시는 분은 언제든지 교회로 연락주시기 바랍니다. 성심성의껏 상담을 해드리겠습니다. 끝으로, 우리교회에서 함께 신앙생활 하기를 원하시는 분은 주저하지 마시고 교회로 연락주시거나 직접 방문해주십시오. 우리교회의 모든 성도들은 여러분을 전심으로 맞이하며 환영할 준비가 되어 있습니다. <strong class="text-gray-900">한가족으로 함께 섬기는 것보다 더 큰 기쁨이 우리에겐 없습니다.</strong> 감사합니다.
                                </p>
                            </div>
                        </div>

                    </div>
                </div>

                <!-- 서명 영역 -->
                <div class="flex justify-end">
                    <div class="text-right bg-primary-50 rounded-3xl px-10 py-8 border border-primary-100 inline-block">
                        <p class="text-sm text-primary-600 font-bold tracking-widest mb-2">부평동부교회</p>
                        <p class="text-3xl font-black text-gray-900 font-serif">강길수 목사</p>
                        <div class="mt-3 w-24 h-0.5 bg-primary-300 ml-auto"></div>
                    </div>
                </div>

            </div>
        {/if}

        {#if activeTab === "people"}
            <div class="animate-fade-in-up" in:fade={{ duration: 400 }}>
                <div class="text-center md:text-left mb-16">
                    <h2
                        class="text-4xl md:text-5xl font-black text-gray-900 font-serif mb-6"
                    >
                        섬기는 분들
                    </h2>
                    <p class="text-xl text-gray-600">
                        부평동부교회를 섬기는 귀한 동역자들을 소개합니다.
                    </p>
                </div>

                <div
                    class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-12"
                >
                    {#each peopleData as person}
                        <div
                            class="text-center group bg-white p-6 md:p-12 rounded-[2.5rem] border border-gray-100 hover:shadow-xl hover:-translate-y-1 transition-all duration-500"
                        >
                            <div
                                class="w-32 h-32 md:w-40 md:h-40 mx-auto rounded-full bg-gray-50 mb-6 md:mb-8 flex items-center justify-center text-gray-300 border-4 border-white shadow-md group-hover:bg-primary-50 group-hover:text-primary-400 group-hover:scale-105 transition-all duration-500 overflow-hidden relative"
                            >
                                <svg
                                    class="w-12 h-12 md:w-16 md:h-16"
                                    fill="currentColor"
                                    viewBox="0 0 24 24"
                                    ><path
                                        d="M12 12c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"
                                    /></svg
                                >
                            </div>

                            <h3
                                class="text-xl md:text-2xl font-bold text-gray-900 mb-2"
                            >
                                {person.name}
                                <span
                                    class="text-base md:text-lg font-medium text-gray-500"
                                    >{person.role}</span
                                >
                            </h3>

                            <div class="space-y-1 mt-4">
                                {#if person.duty}
                                    <p
                                        class="text-sm md:text-base text-primary-600 font-medium break-keep"
                                    >
                                        {person.duty}
                                    </p>
                                {/if}
                                {#if person.phone}
                                    <p class="text-sm text-gray-500 mt-2">
                                        {person.phone}
                                    </p>
                                {/if}
                            </div>
                        </div>
                    {/each}
                </div>
            </div>
        {/if}

        {#if activeTab === "worship"}
            <div class="animate-fade-in-up" in:fade={{ duration: 400 }}>
                <div class="text-center md:text-left mb-16">
                    <h2
                        class="text-4xl md:text-5xl font-black text-gray-900 font-serif mb-6"
                    >
                        예배 안내
                    </h2>
                    <p class="text-xl text-gray-600">
                        신령과 진정으로 드리는 예배의 자리로 여러분을
                        초대합니다.
                    </p>
                </div>

                <!-- 온라인 예배 안내 -->
                <div
                    class="bg-primary-50 rounded-[2.5rem] p-6 md:p-12 mb-12 md:mb-16 border border-primary-100 shadow-sm relative overflow-hidden"
                >
                    <div
                        class="absolute right-0 top-0 opacity-10 pointer-events-none transform translate-x-1/4 -translate-y-1/4"
                    >
                        <svg
                            class="w-64 h-64 text-primary-600"
                            fill="currentColor"
                            viewBox="0 0 24 24"
                            ><path
                                d="M21.582 6.186a2.506 2.506 0 00-1.762-1.766C18.265 4 12 4 12 4s-6.264 0-7.82.42a2.505 2.505 0 00-1.762 1.766C2 7.74 2 12 2 12s0 4.26.418 5.814a2.506 2.506 0 001.762 1.766C5.736 20 12 20 12 20s6.265 0 7.82-.42a2.506 2.506 0 001.762-1.766C22 16.26 22 12 22 12s0-4.26-.418-5.814zM10 15.464V8.536L16 12l-6 3.464z"
                            /></svg
                        >
                    </div>
                    <div class="relative z-10 w-full lg:w-2/3">
                        <h3
                            class="text-2xl font-bold text-primary-800 mb-4 flex items-center gap-3"
                        >
                            <span class="relative flex h-4 w-4">
                                <span
                                    class="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"
                                ></span>
                                <span
                                    class="relative inline-flex rounded-full h-4 w-4 bg-red-500"
                                ></span>
                            </span>
                            온라인 예배 안내
                        </h3>
                        <p
                            class="text-lg text-primary-700 leading-relaxed mb-6 font-medium break-keep"
                        >
                            예배 실황은 부평동부교회 유튜브 채널에서 영상으로
                            확인하실 수 있습니다.<br class="hidden md:block" />
                            영상예배를 드리시는 성도님들은 경건한 몸과 마음으로 참여해주시기를
                            부탁드립니다.
                        </p>
                        <a
                            href="https://www.youtube.com/channel/UCk4rCQhC6Ab-hPNx_-2-CAQ/featured"
                            target="_blank"
                            rel="noopener noreferrer"
                            class="inline-flex items-center justify-center bg-red-600 text-white font-bold py-3.5 px-8 rounded-full shadow-md hover:bg-red-700 hover:shadow-lg transition-all duration-300 transform hover:-translate-y-0.5 whitespace-nowrap"
                        >
                            유튜브 채널 바로가기
                            <svg
                                class="ml-2 w-5 h-5"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                                ><path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M14 5l7 7m0 0l-7 7m7-7H3"
                                ></path></svg
                            >
                        </a>
                    </div>
                </div>

                <!-- 예배 시간표 -->
                <div class="bg-white rounded-[3rem] p-6 md:p-12 shadow-sm border border-gray-100">
                    <h3 class="text-xl md:text-2xl font-bold text-gray-900 mb-6 md:mb-8 border-b-2 border-primary-100 pb-4 inline-block">
                        정규 예배 시간안내
                    </h3>

                    <!-- 모바일: 리스트 레이아웃 -->
                    <div class="md:hidden space-y-5">
                        {#each [
                            { label: '주일', bg: 'bg-primary-50', items: [
                                { name: '1부', time: '09:00', place: '글로리홀' },
                                { name: '2부', time: '11:00', place: '글로리홀' },
                                { name: '오후', time: '14:30', place: '글로리홀' },
                                { name: '새가족', time: '11:00', place: '바나바홀' },
                                { name: '영아부', time: '11:00', place: '본관 1층' },
                                { name: '유치부', time: '11:00', place: '본관 1층' },
                                { name: '유초등부', time: '11:00', place: '본관 1층' },
                                { name: '중고등부', time: '11:00', place: '다니엘관' },
                                { name: '청년부', time: '14:00', place: '다니엘관' },
                            ]},
                            { label: '주중', bg: 'bg-gray-50', items: [
                                { name: '수요예배 (WBA)', time: '20:00', place: '글로리홀' },
                                { name: '금요기도회', time: '21:00', place: '글로리홀' },
                                { name: '새벽기도회', time: '05:00', place: '글로리홀' },
                            ]},
                        ] as group}
                            <div class="rounded-2xl overflow-hidden border border-gray-100">
                                <div class="px-4 py-2.5 {group.bg} font-bold text-primary-800 text-sm">
                                    {group.label}
                                </div>
                                <div class="divide-y divide-gray-100">
                                    {#each group.items as item}
                                        <div class="flex items-center px-4 py-3 gap-3">
                                            <span class="w-24 shrink-0 text-sm font-medium text-gray-800">{item.name}</span>
                                            <span class="text-sm font-medium text-gray-500 w-14 shrink-0">{item.time}</span>
                                            <span class="text-sm font-medium text-primary-700">{item.place}</span>
                                        </div>
                                    {/each}
                                </div>
                            </div>
                        {/each}
                    </div>

                    <!-- 데스크탑: 테이블 레이아웃 -->
                    <div class="hidden md:block overflow-x-auto">
                        <table class="w-full border-collapse min-w-140 text-center">
                            <thead>
                                <tr class="bg-primary-800 text-white">
                                    <th class="py-4 px-6 font-bold text-base w-20"></th>
                                    <th class="py-4 px-6 font-bold text-base border-l border-primary-700">예배</th>
                                    <th class="py-4 px-6 font-bold text-base border-l border-primary-700">시간</th>
                                    <th class="py-4 px-6 font-bold text-base border-l border-primary-700">장소</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-200 text-gray-800 text-base">
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td rowspan="9" class="font-bold text-primary-800 text-lg border-r border-gray-200 bg-primary-50/60">주일</td>
                                    <td class="py-4 px-6 border-l border-gray-200">1부</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">09:00</td>
                                    <td rowspan="3" class="py-4 px-6 font-medium text-primary-700 border-l border-gray-200 bg-primary-50/30">글로리홀</td>
                                </tr>
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">2부</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">11:00</td>
                                </tr>
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">오후</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">14:30</td>
                                </tr>
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">새가족</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">11:00</td>
                                    <td class="py-4 px-6 font-medium text-primary-700 border-l border-gray-200 bg-primary-50/30">바나바홀</td>
                                </tr>
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">영아부</td>
                                    <td rowspan="3" class="py-4 px-6 font-medium border-l border-gray-200">11:00</td>
                                    <td rowspan="3" class="py-4 px-6 font-medium text-primary-700 border-l border-gray-200 bg-primary-50/30">본관 1층</td>
                                </tr>
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">유치부</td>
                                </tr>
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">유초등부</td>
                                </tr>
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">중고등부</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">11:00</td>
                                    <td rowspan="2" class="py-4 px-6 font-medium text-primary-700 border-l border-gray-200 bg-primary-50/30">다니엘관</td>
                                </tr>
                                <tr class="hover:bg-primary-50/40 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">청년부</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">14:00</td>
                                </tr>
                                <tr class="hover:bg-gray-50 transition-colors border-t-2 border-gray-300">
                                    <td rowspan="3" class="font-bold text-primary-800 text-lg border-r border-gray-200 bg-gray-50">주중</td>
                                    <td class="py-4 px-6 border-l border-gray-200">수요예배 (WBA)</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">20:00</td>
                                    <td rowspan="3" class="py-4 px-6 font-medium text-primary-700 border-l border-gray-200 bg-primary-50/30">글로리홀</td>
                                </tr>
                                <tr class="hover:bg-gray-50 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">금요기도회</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">21:00</td>
                                </tr>
                                <tr class="hover:bg-gray-50 transition-colors">
                                    <td class="py-4 px-6 border-l border-gray-200">새벽기도회</td>
                                    <td class="py-4 px-6 font-medium border-l border-gray-200">05:00</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        {/if}

        {#if activeTab === "map"}
            <div class="animate-fade-in-up" in:fade={{ duration: 400 }}>
                <div class="text-center md:text-left mb-16">
                    <h2
                        class="text-4xl md:text-5xl font-black text-gray-900 font-serif mb-6"
                    >
                        오시는 길
                    </h2>
                    <p class="text-xl text-gray-600">
                        예배의 자리로 나아오시는 발걸음을 환영합니다.
                    </p>
                </div>

                <div
                    class="bg-gray-100 w-full h-[500px] md:h-[600px] rounded-[3rem] mb-16 flex items-center justify-center border-4 border-white shadow-lg overflow-hidden relative"
                >
                    <iframe
                        title="부평동부교회 지도"
                        width="100%"
                        height="100%"
                        style="border:0;"
                        loading="lazy"
                        referrerpolicy="no-referrer-when-downgrade"
                        src="https://maps.google.com/maps?width=100%25&amp;height=600&amp;hl=ko&amp;q=%EC%9D%B8%EC%B2%9C%EA%B4%91%EC%97%AD%EC%8B%9C%20%EB%B6%80%ED%8F%89%EA%B5%AC%20%EC%8B%9C%EC%9E%A5%EB%A1%9C%2064+(%EB%B6%80%ED%8F%89%EB%8F%99%EB%B6%80%EA%B5%90%ED%9A%8C)&amp;t=&amp;z=15&amp;ie=UTF8&amp;iwloc=B&amp;output=embed"
                    ></iframe>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-2 gap-12">
                    <div
                        class="p-6 md:p-12 bg-white rounded-[2.5rem] border border-gray-100 shadow-sm hover:shadow-md transition-shadow"
                    >
                        <h3
                            class="text-2xl font-black text-gray-900 mb-10 flex items-center gap-4"
                        >
                            <span
                                class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center text-primary-600"
                            >
                                <svg
                                    class="w-8 h-8"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                    ><path
                                        stroke-linecap="round"
                                        stroke-linejoin="round"
                                        stroke-width="2"
                                        d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"
                                    ></path></svg
                                >
                            </span>
                            대중교통 이용안내
                        </h3>
                        <ul class="text-base md:text-xl text-gray-700 space-y-8">
                            <li class="flex flex-col gap-4">
                                <div class="flex items-center">
                                    <span
                                        class="inline-flex px-4 py-1 bg-green-100 text-green-700 rounded-lg font-bold text-base shadow-sm shrink-0"
                                        >지하철</span
                                    >
                                </div>
                                <div class="pl-2 space-y-3">
                                    <p class="flex items-start gap-3">
                                        <span
                                            class="w-1.5 h-1.5 rounded-full bg-gray-400 mt-2.5 shrink-0"
                                        ></span>
                                        <span
                                            ><strong class="text-gray-900"
                                                >부평역(1호선/인천1호선) 7번출구</strong
                                            ><br /><span
                                                class="text-gray-600 text-lg"
                                                >지하상가 20-B출구에서 도보로
                                                10분</span
                                            ></span
                                        >
                                    </p>
                                    <p class="flex items-start gap-3">
                                        <span
                                            class="w-1.5 h-1.5 rounded-full bg-gray-400 mt-2.5 shrink-0"
                                        ></span>
                                        <span
                                            ><strong class="text-gray-900"
                                                >부평시장역(1호선/인천1호선)
                                                2번출구</strong
                                            ><br /><span
                                                class="text-gray-600 text-lg"
                                                >부평시장 통과하여 도보로 10분</span
                                            ></span
                                        >
                                    </p>
                                </div>
                            </li>
                            <li
                                class="flex flex-col gap-4 mt-8 pt-8 border-t border-gray-100"
                            >
                                <div class="flex items-center">
                                    <span
                                        class="inline-flex px-4 py-1 bg-blue-100 text-blue-700 rounded-lg font-bold text-base shadow-sm shrink-0"
                                        >시내버스</span
                                    >
                                </div>
                                <div class="pl-2">
                                    <p class="flex items-start gap-3">
                                        <span
                                            class="w-1.5 h-1.5 rounded-full bg-gray-400 mt-2.5 shrink-0"
                                        ></span>
                                        <span
                                            ><strong class="text-gray-900"
                                                >10, 23, 24-1, 35, 45</strong
                                            ><br /><span
                                                class="text-gray-600 text-lg"
                                                >부평시장 정류장 하차 후 도보로
                                                2분</span
                                            ></span
                                        >
                                    </p>
                                </div>
                            </li>
                        </ul>
                    </div>

                    <div
                        class="p-6 md:p-12 bg-white rounded-[2.5rem] border border-gray-100 shadow-sm hover:shadow-md transition-shadow"
                    >
                        <h3
                            class="text-2xl font-black text-gray-900 mb-10 flex items-center gap-4"
                        >
                            <span
                                class="w-14 h-14 bg-primary-50 rounded-2xl flex items-center justify-center text-primary-600"
                            >
                                <svg
                                    class="w-8 h-8"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                    ><path
                                        stroke-linecap="round"
                                        stroke-linejoin="round"
                                        stroke-width="2"
                                        d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                                    ></path></svg
                                >
                            </span>
                            주차 안내
                        </h3>
                        <div class="space-y-6">
                            <ul class="text-xl text-gray-700 space-y-4">
                                <li class="flex items-start gap-4">
                                    <span
                                        class="inline-flex px-4 py-1.5 bg-gray-100 text-gray-700 rounded-xl font-bold text-lg shadow-sm shrink-0"
                                        >제 1 주차장</span
                                    >
                                    <span class="pt-1 font-medium"
                                        >교회 본관 위치</span
                                    >
                                </li>
                                <li class="flex items-start gap-4">
                                    <span
                                        class="inline-flex px-4 py-1.5 bg-gray-100 text-gray-700 rounded-xl font-bold text-lg shadow-sm shrink-0"
                                        >제 2 주차장</span
                                    >
                                    <span class="pt-1 font-medium"
                                        >다니엘관 옆 위치</span
                                    >
                                </li>
                            </ul>

                            <div class="mt-8 pt-8 border-t border-gray-100">
                                <h4
                                    class="text-xl font-bold text-gray-900 mb-6"
                                >
                                    교회 연락처
                                </h4>
                                <ul
                                    class="text-lg text-gray-700 space-y-3 font-medium"
                                >
                                    <li class="flex gap-6">
                                        <span class="w-14 text-gray-400"
                                            >전화</span
                                        >
                                        <strong class="text-primary-600"
                                            >032-515-1401</strong
                                        >
                                    </li>
                                    <li class="flex gap-6">
                                        <span class="w-14 text-gray-400"
                                            >팩스</span
                                        > 032-515-1403
                                    </li>
                                    <li class="flex gap-6">
                                        <span class="w-14 text-gray-400"
                                            >이메일</span
                                        > hello@dbchurch.net
                                    </li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        {/if}
    </div>
</div>
