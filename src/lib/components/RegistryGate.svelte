<script lang="ts">
    import { onMount, type Snippet } from 'svelte';
    import { goto } from '$app/navigation';
    import { loadRegistryMe, mfaStatus, mfaEnroll, mfaVerify, type RegistryMe } from '$lib/registry';
    import RegistryNav from '$lib/components/RegistryNav.svelte';

    // 교적 화면 공통 관문: 권한 확인 → 2단계 인증(처음이면 인증 앱 등록) → 화면.
    // 쓰지 않고 idle_minutes 가 지나면 화면을 내리고 다시 인증 코드를 받는다.
    // children 은 확인이 끝난 뒤에만 그려지므로, 안쪽 컴포넌트의 onMount 는 권한이 확인된 상태에서 돈다.
    let {
        need = 'view',
        children
    }: { need?: 'view' | 'edit' | 'admin'; children: Snippet<[RegistryMe]> } = $props();

    let me = $state<RegistryMe | null>(null);
    let phase = $state<'loading' | 'denied' | 'mfa' | 'locked' | 'ready'>('loading');
    let deniedText = $state('');

    let factorId = $state<string | null>(null);
    let enrolling = $state<{ qr: string; secret: string } | null>(null);
    let showSecret = $state(false);
    let code = $state('');
    let mfaError = $state('');
    let busy = $state(false);

    let lastActive = Date.now();

    function deny(text: string) {
        deniedText = text;
        phase = 'denied';
    }

    async function refresh() {
        const { hasSession, me: m } = await loadRegistryMe();
        if (!hasSession) return goto('/login');
        me = m;
        if (!m) return deny('권한을 확인하지 못했습니다. 잠시 뒤 다시 시도해 주세요.');
        const allowed = need === 'admin' ? m.is_admin : need === 'edit' ? m.is_staff && m.can_edit : m.is_staff;
        if (!allowed) {
            return deny(
                need === 'admin'
                    ? '사이트 관리자만 볼 수 있습니다.'
                    : need === 'edit'
                      ? '교적 수정 권한이 있는 사람만 할 수 있습니다.'
                      : '교적 권한이 있는 사람만 볼 수 있습니다.'
            );
        }
        if (m.mfa_required && m.aal !== 'aal2') return startMfa();
        lastActive = Date.now();
        phase = 'ready';
    }

    async function startMfa() {
        mfaError = '';
        enrolling = null;
        const s = await mfaStatus();
        factorId = s.factorId;
        if (!factorId) {
            const r = await mfaEnroll();
            if ('error' in r) {
                mfaError = r.error;
            } else {
                factorId = r.factorId;
                enrolling = { qr: r.qr, secret: r.secret };
            }
        }
        phase = 'mfa';
    }

    async function lock() {
        phase = 'locked';
        code = '';
        mfaError = '';
        factorId = (await mfaStatus()).factorId;
    }

    async function submitCode(e: SubmitEvent) {
        e.preventDefault();
        if (busy) return;
        if (!factorId) {
            // 2단계 인증 스위치를 끈 상태에서 잠긴 경우
            await refresh();
            return;
        }
        if (!/^\d{6}$/.test(code.trim())) {
            mfaError = '6자리 숫자를 넣어 주세요.';
            return;
        }
        busy = true;
        mfaError = '';
        const err = await mfaVerify(factorId, code);
        busy = false;
        if (err) {
            mfaError = err;
            return;
        }
        code = '';
        enrolling = null;
        await refresh();
    }

    onMount(() => {
        refresh();
        const bump = () => (lastActive = Date.now());
        const events = ['mousemove', 'keydown', 'click', 'touchstart', 'scroll'] as const;
        events.forEach((ev) => window.addEventListener(ev, bump, { passive: true }));
        const timer = setInterval(() => {
            if (phase === 'ready' && me && Date.now() - lastActive > me.idle_minutes * 60_000) lock();
        }, 20_000);
        return () => {
            events.forEach((ev) => window.removeEventListener(ev, bump));
            clearInterval(timer);
        };
    });
</script>

<svelte:head><title>교적 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">교적</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">교인의 재적·세대·신급·직분을 관리합니다. 모든 조회와 수정은 접속기록에 남습니다.</p>

    {#if phase === 'loading'}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if phase === 'denied'}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
            <p class="text-gray-400 text-sm mt-2">{deniedText}</p>
            {#if me?.is_admin && need !== 'admin'}
                <a href="/registry/admin" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">교적 권한 관리로</a>
            {/if}
        </div>
    {:else if phase === 'mfa' || phase === 'locked'}
        <div class="max-w-md mx-auto rounded-2xl border border-gray-200 bg-white p-6 mt-4">
            {#if phase === 'locked'}
                <h2 class="text-lg font-black text-gray-900 mb-1">화면을 잠갔습니다</h2>
                <p class="text-sm text-gray-500 mb-5">{me?.idle_minutes ?? 30}분 동안 사용하지 않아 교적 화면을 내렸습니다. 다시 열려면 인증 코드를 넣어 주세요.</p>
            {:else if enrolling}
                <h2 class="text-lg font-black text-gray-900 mb-1">2단계 인증 등록</h2>
                <p class="text-sm text-gray-500 mb-4">
                    교적에는 2단계 인증이 필요합니다. 휴대폰의 인증 앱(Google Authenticator, Microsoft Authenticator 등)으로
                    아래 QR 코드를 찍은 뒤, 앱에 나온 6자리 코드를 넣어 주세요. 한 번 등록하면 다음부터는 코드만 넣으면 됩니다.
                </p>
                <img src={enrolling.qr} alt="인증 앱 등록 QR 코드" class="w-44 h-44 mx-auto mb-3 bg-white" />
                <div class="text-center mb-4">
                    <button type="button" onclick={() => (showSecret = !showSecret)} class="text-xs text-gray-500 underline">
                        QR을 찍을 수 없으면 키를 직접 입력
                    </button>
                    {#if showSecret}
                        <div class="mt-2 font-mono text-sm bg-gray-50 rounded-lg px-3 py-2 break-all select-all">{enrolling.secret}</div>
                    {/if}
                </div>
            {:else}
                <h2 class="text-lg font-black text-gray-900 mb-1">2단계 인증</h2>
                <p class="text-sm text-gray-500 mb-5">인증 앱에 나온 6자리 코드를 넣어 주세요.</p>
            {/if}

            <form onsubmit={submitCode} class="flex gap-2">
                {#if factorId}
                    <input type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" bind:value={code} placeholder="000000"
                        class="flex-1 px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-mono text-lg tracking-widest text-center" />
                {/if}
                <button type="submit" disabled={busy}
                    class="px-5 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-50 {factorId ? '' : 'flex-1'}">
                    {factorId ? '확인' : '다시 열기'}
                </button>
            </form>
            {#if mfaError}<p class="mt-3 text-sm text-red-600">{mfaError}</p>{/if}
        </div>
    {:else if me}
        <RegistryNav {me} />
        {@render children(me)}
    {/if}
</div>
