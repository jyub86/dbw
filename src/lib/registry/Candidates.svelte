<script lang="ts">
    import { onMount } from 'svelte';
    import { call, fmtDateTime, type RegistryMe } from '$lib/registry';

    let { me }: { me: RegistryMe } = $props();

    type Candidate = { person_id: string; name: string | null; office: string | null; member: boolean; has_account: boolean; group_name: string | null; reason: string };
    type Conflict = { id: number; detected_at: string; account_id: string; account_name: string | null; profile_id: string; profile_name: string | null };

    const REASON: Record<string, { title: string; help: string }> = {
        no_group: { title: '목장이 없는 교인', help: '교인으로 표시돼 있지만 어느 목장에도 없습니다. 교회에 계속 출석하는 분이면 교적에 올리세요.' },
        left_group: { title: '목장 명단에서 빠진 교인', help: '목장 명단에서 제외된 분입니다. 교회를 떠났다면 그대로 두세요.' },
        not_member: { title: '교인 인증 전 목장 구성원', help: '목장에는 있지만 앱의 교인 인증이 안 된 분입니다. 등록 교인이면 교적에 올리세요(교인 인증도 함께 켜집니다).' }
    };

    let rows = $state<Candidate[]>([]);
    let conflicts = $state<Conflict[]>([]);
    let loading = $state(true);
    let msg = $state('');
    let errorMsg = $state('');
    let busyId = $state<string | null>(null);

    const groups = $derived(
        Object.keys(REASON).map((k) => ({ key: k, items: rows.filter((r) => r.reason === k) })).filter((g) => g.items.length)
    );

    async function load() {
        const [a, b] = await Promise.all([
            call<Candidate[]>('registry_candidates', {}, '목록을 불러오지 못했습니다.'),
            call<Conflict[]>('registry_merge_conflicts', {}, '병합 충돌을 불러오지 못했습니다.')
        ]);
        loading = false;
        if (!a.ok) return (errorMsg = a.error);
        rows = a.data;
        conflicts = b.ok ? b.data : [];
    }

    async function enroll(c: Candidate) {
        busyId = c.person_id;
        const r = await call('registry_enroll', { p_person_id: c.person_id }, '교적에 올리지 못했습니다.');
        busyId = null;
        if (!r.ok) {
            errorMsg = r.error;
            return;
        }
        errorMsg = '';
        msg = `${c.name ?? ''}님을 교적에 올렸습니다.`;
        rows = rows.filter((x) => x.person_id !== c.person_id);
    }

    onMount(load);
</script>

{#if msg}<div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>{/if}
{#if errorMsg}<div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>{/if}

{#if loading}
    <div class="py-16 text-center text-gray-400 text-sm">불러오는 중…</div>
{:else}
    <p class="text-sm text-gray-500 mb-6">처음 교적을 만들 때 자동으로 올리지 않은 분들입니다. 한 분씩 확인해서 교적에 올리세요. 올린 뒤에는 이 목록에서 빠집니다.</p>

    {#if conflicts.length > 0}
        <section class="mb-10">
            <h2 class="text-base font-black text-gray-900 mb-1">가입 병합 충돌 <span class="text-red-500">{conflicts.length}</span></h2>
            <p class="text-xs text-gray-500 mb-3">
                앱 가입자와 이름·전화번호가 같은 미가입 교인이 있는데, 두 사람 모두 교적이 있어 자동으로 합치지 못했습니다.
                같은 사람이면 한쪽 교적을 '잘못 만든 교적 지우기'로 지운 뒤, 미가입 쪽 카드에서 '가입한 계정과 연결'을 하세요.
            </p>
            <div class="rounded-2xl border border-gray-200 overflow-hidden">
                {#each conflicts as c (c.id)}
                    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 border-b border-gray-50 last:border-0 text-sm">
                        <span class="text-xs text-gray-400">{fmtDateTime(c.detected_at)}</span>
                        <a href={`/registry/${c.account_id}`} class="font-bold text-gray-900 hover:text-primary-700">{c.account_name} <span class="text-xs text-blue-600">(앱 가입)</span></a>
                        <span class="text-gray-400">↔</span>
                        <a href={`/registry/${c.profile_id}`} class="font-bold text-gray-900 hover:text-primary-700">{c.profile_name} <span class="text-xs text-gray-400">(미가입)</span></a>
                    </div>
                {/each}
            </div>
        </section>
    {/if}

    {#if groups.length === 0}
        <div class="py-16 text-center text-gray-400 text-sm">확인할 사람이 없습니다.</div>
    {/if}
    {#each groups as g (g.key)}
        <section class="mb-10">
            <h2 class="text-base font-black text-gray-900 mb-1">{REASON[g.key].title} <span class="text-gray-400">{g.items.length}</span></h2>
            <p class="text-xs text-gray-500 mb-3">{REASON[g.key].help}</p>
            <div class="rounded-2xl border border-gray-200 overflow-hidden">
                {#each g.items as c (c.person_id)}
                    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2.5 border-b border-gray-50 last:border-0 text-sm">
                        <b class="text-gray-900">{c.name ?? '(이름없음)'}</b>
                        <span class="text-xs text-gray-500">{c.office ?? ''}</span>
                        {#if c.group_name}<span class="text-xs text-gray-400">{c.group_name}</span>{/if}
                        {#if c.has_account}<span class="text-xs text-blue-600">앱 가입</span>{/if}
                        {#if me.can_edit}
                            <button type="button" onclick={() => enroll(c)} disabled={busyId === c.person_id}
                                class="ml-auto px-3 py-1.5 rounded-lg text-xs font-bold bg-primary-900 text-white disabled:opacity-50">교적에 올리기</button>
                        {/if}
                    </div>
                {/each}
            </div>
        </section>
    {/each}
{/if}
