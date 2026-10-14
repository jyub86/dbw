<script lang="ts">
    import { onMount, type Snippet } from 'svelte';
    import { goto } from '$app/navigation';
    import { loadRegistryMe, passwordSet, unlock, touch, lockSession, type RegistryMe } from '$lib/registry';
    import RegistryNav from '$lib/components/RegistryNav.svelte';

    // 교적 화면 공통 관문: 권한 확인 → 교적 비밀번호(처음이면 정하기) → 화면.
    // 쓰는 동안 몇 분마다 서버 쪽 세션을 늘리고, 쓰지 않고 idle_minutes 가 지나면 화면을 내리고 다시 비밀번호를 받는다.
    // children 은 확인이 끝난 뒤에만 그려지므로, 안쪽 컴포넌트의 onMount 는 권한이 확인된 상태에서 돈다.
    let {
        need = 'view',
        children
    }: { need?: 'view' | 'edit' | 'admin'; children: Snippet<[RegistryMe]> } = $props();

    const TOUCH_MS = 2 * 60_000;

    let me = $state<RegistryMe | null>(null);
    let phase = $state<'loading' | 'denied' | 'password' | 'ready'>('loading');
    let deniedText = $state('');
    let idleLocked = $state(false);

    let pw = $state('');
    let pw2 = $state('');
    let showPw = $state(false);
    let pwError = $state('');
    let busy = $state(false);

    let lastActive = Date.now();
    let lastTouch = Date.now();

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
        if (m.password_required && !m.unlocked) {
            pw = '';
            pw2 = '';
            phase = 'password';
            return;
        }
        idleLocked = false;
        lastActive = lastTouch = Date.now();
        phase = 'ready';
    }

    async function lock() {
        idleLocked = true;
        pw = '';
        pwError = '';
        phase = 'password';
        await lockSession();
    }

    const pwProblem = (p: string) =>
        p.length < 8 ? '8자 이상으로 정해 주세요.' : p.length > 64 ? '64자까지 쓸 수 있습니다.' : !/[0-9]/.test(p) || !/[A-Za-z]/.test(p) ? '영문과 숫자를 섞어 주세요.' : '';

    async function submit(e: SubmitEvent) {
        e.preventDefault();
        if (busy || !me) return;
        pwError = '';
        if (!me.password_set) {
            const why = pwProblem(pw);
            if (why) return (pwError = why);
            if (pw !== pw2) return (pwError = '두 번 넣은 비밀번호가 다릅니다.');
            busy = true;
            const err = await passwordSet(pw);
            busy = false;
            if (err) return (pwError = err);
        } else {
            if (!pw) return (pwError = '비밀번호를 넣어 주세요.');
            busy = true;
            const r = await unlock(pw);
            busy = false;
            if (!r.ok) {
                pw = '';
                if (r.reason === 'error') return (pwError = r.error);
                if (r.reason === 'wrong') return (pwError = `비밀번호가 맞지 않습니다. ${r.left}번 더 틀리면 잠깁니다.`);
                // 잠겼거나(locked) 그 사이 초기화됐으면(not_set) 다시 읽어 맞는 화면을 보여 준다
                return refresh();
            }
        }
        pw = '';
        pw2 = '';
        await refresh();
    }

    onMount(() => {
        refresh();
        const bump = () => (lastActive = Date.now());
        const events = ['mousemove', 'keydown', 'click', 'touchstart', 'scroll'] as const;
        events.forEach((ev) => window.addEventListener(ev, bump, { passive: true }));
        const timer = setInterval(async () => {
            if (phase !== 'ready' || !me?.password_required) return;
            const now = Date.now();
            if (now - lastActive > me.idle_minutes * 60_000) return lock();
            // 최근에 쓴 적이 있으면 서버 쪽 세션도 늘린다. 다른 탭에서 잠갔으면 여기서도 잠근다
            if (now - lastTouch > TOUCH_MS && now - lastActive < TOUCH_MS) {
                lastTouch = now;
                if (!(await touch())) lock();
            }
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
    {:else if phase === 'password' && me}
        <div class="max-w-md mx-auto rounded-2xl border border-gray-200 bg-white p-6 mt-4">
            {#if me.locked_out}
                <h2 class="text-lg font-black text-gray-900 mb-1">교적 비밀번호가 잠겼습니다</h2>
                <p class="text-sm text-gray-500 break-keep">
                    비밀번호를 5번 틀려서 잠갔습니다. 사이트 관리자에게 '권한·기록'에서 비밀번호 초기화를 부탁해 주세요.
                    초기화하면 다음에 들어올 때 비밀번호를 새로 정합니다.
                </p>
            {:else}
                {#if !me.password_set}
                    <h2 class="text-lg font-black text-gray-900 mb-1">교적 비밀번호 정하기</h2>
                    <p class="text-sm text-gray-500 mb-5 break-keep">
                        교적에 들어갈 때마다 넣을 비밀번호를 정해 주세요. <b>영문과 숫자를 섞어 8자 이상</b>으로, 카카오 비밀번호와는 다르게 정합니다.
                    </p>
                {:else if idleLocked}
                    <h2 class="text-lg font-black text-gray-900 mb-1">화면을 잠갔습니다</h2>
                    <p class="text-sm text-gray-500 mb-5 break-keep">{me.idle_minutes}분 동안 사용하지 않아 교적 화면을 내렸습니다. 교적 비밀번호를 넣으면 다시 열립니다.</p>
                {:else}
                    <h2 class="text-lg font-black text-gray-900 mb-1">교적 비밀번호</h2>
                    <p class="text-sm text-gray-500 mb-5 break-keep">처음에 정한 교적 비밀번호를 넣어 주세요.</p>
                {/if}

                <form onsubmit={submit} class="space-y-2">
                    <input type={showPw ? 'text' : 'password'} bind:value={pw} placeholder={me.password_set ? '교적 비밀번호' : '새 비밀번호'}
                        autocomplete={me.password_set ? 'current-password' : 'new-password'}
                        class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-base" />
                    {#if !me.password_set}
                        <input type={showPw ? 'text' : 'password'} bind:value={pw2} placeholder="한 번 더" autocomplete="new-password"
                            class="w-full px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-base" />
                    {/if}
                    <div class="flex items-center justify-between pt-1">
                        <label class="flex items-center gap-1.5 text-xs text-gray-500"><input type="checkbox" bind:checked={showPw} /> 비밀번호 보기</label>
                        <button type="submit" disabled={busy}
                            class="px-5 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-50">
                            {me.password_set ? '확인' : '정하기'}
                        </button>
                    </div>
                </form>
                {#if pwError}<p class="mt-3 text-sm text-red-600">{pwError}</p>{/if}
                <p class="mt-5 text-xs text-gray-400 break-keep">5번 틀리면 잠깁니다. 비밀번호를 잊으셨으면 사이트 관리자에게 초기화를 부탁해 주세요.</p>
            {/if}
        </div>
    {:else if me}
        <RegistryNav {me} />
        {@render children(me)}
    {/if}
</div>
