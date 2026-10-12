<script lang="ts">
    import { onMount } from 'svelte';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { call, fmtDateTime, today } from '$lib/registry';

    type Staff = { user_id: string; name: string | null; office: string | null; can_edit: boolean; can_export: boolean; can_pastoral: boolean; note: string | null; granted_at: string; granted_by_name: string | null };
    type PermLog = { id: number; at: string; area: string; op: string; subject_name: string | null; actor_name: string | null; old_value: Record<string, unknown> | null; new_value: Record<string, unknown> | null };
    type AccessLog = { id: number; at: string; actor_name: string | null; ip: string | null; user_agent: string | null; action: string; fn: string; target_count: number; target_names: string[] | null; detail: Record<string, unknown> | null };
    type Profile = { id: string; name: string | null; office: string | null; phone: string | null; active: boolean };

    const ACTION: Record<string, string> = { search: '검색', view: '열람', create: '등록', update: '수정', delete: '삭제', export: '내려받기', print: '출력' };
    const OP: Record<string, string> = { grant: '부여', change: '변경', revoke: '해제' };

    let view = $state<'staff' | 'access' | 'perm'>('staff');
    let msg = $state('');
    let errorMsg = $state('');

    // ─── 교적 권한 ───
    let staff = $state<Staff[]>([]);
    let addOpen = $state(false);
    let addQuery = $state('');
    let addResults = $state<Profile[]>([]);

    async function loadStaff() {
        const r = await call<Staff[]>('registry_staff_list', {}, '담당자 목록을 불러오지 못했습니다.');
        if (!r.ok) return (errorMsg = r.error);
        staff = r.data;
    }

    async function searchProfiles() {
        const t = addQuery.trim();
        if (!t) return (addResults = []);
        const { data } = await supabaseBrowser
            .from('custom_users')
            .select('id, name, office, phone, active')
            .ilike('name', `%${t}%`)
            .order('active', { ascending: false })
            .order('name')
            .limit(30);
        addResults = (data ?? []) as Profile[];
    }

    async function setStaff(s: Pick<Staff, 'user_id' | 'can_edit' | 'can_export' | 'can_pastoral' | 'note'>, ok: string) {
        const r = await call('registry_staff_set', {
            p_user_id: s.user_id, p_can_edit: s.can_edit, p_can_export: s.can_export, p_can_pastoral: s.can_pastoral, p_note: s.note
        }, '권한을 저장하지 못했습니다.');
        if (!r.ok) return (errorMsg = r.error);
        errorMsg = '';
        msg = ok;
        await loadStaff();
    }

    async function addStaff(p: Profile) {
        await setStaff({ user_id: p.id, can_edit: false, can_export: false, can_pastoral: false, note: null }, `${p.name}님에게 교적 열람 권한을 주었습니다.`);
        addOpen = false;
        addQuery = '';
        addResults = [];
    }

    async function removeStaff(s: Staff) {
        const r = await call('registry_staff_remove', { p_user_id: s.user_id }, '해제하지 못했습니다.');
        if (!r.ok) return (errorMsg = r.error);
        msg = `${s.name}님의 교적 권한을 해제했습니다.`;
        await loadStaff();
    }

    // ─── 접속기록 ───
    const weekAgo = () => new Date(Date.now() - 7 * 86400_000).toLocaleDateString('sv-SE');
    let from = $state(weekAgo());
    let to = $state(today());
    let access = $state<AccessLog[]>([]);
    let accessMore = $state(false);
    const ACCESS_PAGE = 100;

    async function loadAccess(reset = true) {
        const offset = reset ? 0 : access.length;
        // 끝 날짜는 그날 하루를 포함하도록 다음 날 0시까지
        const end = new Date(`${to}T00:00:00`);
        end.setDate(end.getDate() + 1);
        const r = await call<AccessLog[]>('privacy_access_logs', {
            p_from: new Date(`${from}T00:00:00`).toISOString(), p_to: end.toISOString(),
            p_limit: ACCESS_PAGE, p_offset: offset
        }, '접속기록을 불러오지 못했습니다.');
        if (!r.ok) return (errorMsg = r.error);
        access = reset ? r.data : [...access, ...r.data];
        accessMore = r.data.length === ACCESS_PAGE;
    }

    // ─── 권한 이력 ───
    let perms = $state<PermLog[]>([]);
    async function loadPerms() {
        const r = await call<PermLog[]>('privacy_permission_logs', { p_limit: 200 }, '권한 이력을 불러오지 못했습니다.');
        if (!r.ok) return (errorMsg = r.error);
        perms = r.data;
    }
    const flags = (v: Record<string, unknown> | null) =>
        v ? [v.can_edit ? '수정' : '', v.can_export ? '내려받기' : '', v.can_pastoral ? '심방' : ''].filter(Boolean).join('·') || '열람' : '';

    function switchView(v: typeof view) {
        view = v;
        msg = '';
        errorMsg = '';
        if (v === 'access') loadAccess(true);
        if (v === 'perm') loadPerms();
    }

    onMount(loadStaff);
</script>

<div class="flex gap-1 mb-6 bg-gray-100 rounded-2xl p-1 w-fit">
    {#each [['staff', '교적 권한'], ['access', '접속기록'], ['perm', '권한 이력']] as [k, name]}
        <button type="button" onclick={() => switchView(k as typeof view)}
            class="px-4 py-2 rounded-xl text-sm font-bold transition-colors {view === k ? 'bg-white text-primary-800 shadow-sm' : 'text-gray-500 hover:text-gray-800'}">{name}</button>
    {/each}
</div>

{#if msg}<div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>{/if}
{#if errorMsg}<div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>{/if}

{#if view === 'staff'}
    <div class="flex items-center justify-between mb-3">
        <p class="text-xs text-gray-500">교적 권한이 있는 사람은 <b>모든 교인의 교적</b>을 열람합니다. 수정·내려받기·심방은 따로 켭니다. 부여·변경·해제는 권한 이력에 3년 남습니다.</p>
        <button type="button" onclick={() => { addOpen = !addOpen; addQuery = ''; addResults = []; }}
            class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700 shrink-0 ml-4">+ 담당자 추가</button>
    </div>

    {#if addOpen}
        <div class="rounded-2xl border border-gray-200 p-4 mb-4 bg-gray-50">
            <input type="text" placeholder="이름으로 검색" bind:value={addQuery} oninput={searchProfiles}
                class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 mb-2" />
            <div class="max-h-56 overflow-y-auto divide-y divide-gray-100 bg-white rounded-lg">
                {#each addResults as r}
                    <button type="button" disabled={!r.active} onclick={() => addStaff(r)}
                        class="w-full text-left px-3 py-2 hover:bg-primary-50 text-sm flex justify-between disabled:opacity-40 disabled:hover:bg-transparent">
                        <span class="font-medium">{r.name}{#if !r.active}<span class="ml-1 text-[10px] text-gray-400 font-normal">(미가입 — 권한 불가)</span>{/if}</span>
                        <span class="text-gray-400 text-xs">{r.office} · {r.phone || '번호없음'}</span>
                    </button>
                {/each}
                {#if addQuery && addResults.length === 0}<div class="px-3 py-3 text-sm text-gray-400">검색 결과 없음</div>{/if}
            </div>
        </div>
    {/if}

    <div class="rounded-2xl border border-gray-200 overflow-x-auto">
        <table class="w-full text-sm min-w-[40rem]">
            <thead class="bg-gray-50 text-xs text-gray-500">
                <tr>
                    <th class="text-left font-bold px-4 py-2">담당자</th>
                    <th class="font-bold px-3 py-2">열람</th>
                    <th class="font-bold px-3 py-2">수정</th>
                    <th class="font-bold px-3 py-2">내려받기</th>
                    <th class="font-bold px-3 py-2">심방</th>
                    <th class="text-left font-bold px-3 py-2">부여</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
                {#if staff.length === 0}
                    <tr><td colspan="7" class="px-4 py-6 text-center text-gray-400">지정된 담당자가 없습니다.</td></tr>
                {/if}
                {#each staff as s (s.user_id)}
                    <tr class="border-t border-gray-50">
                        <td class="px-4 py-2.5"><b class="text-gray-900">{s.name}</b> <span class="text-xs text-gray-400">{s.office ?? ''}</span></td>
                        <td class="px-3 py-2.5 text-center text-gray-400">✓</td>
                        {#each ['can_edit', 'can_export', 'can_pastoral'] as const as key}
                            <td class="px-3 py-2.5 text-center">
                                <input type="checkbox" checked={s[key]}
                                    onchange={(e) => setStaff({ ...s, [key]: (e.currentTarget as HTMLInputElement).checked }, `${s.name}님의 권한을 바꿨습니다.`)} />
                            </td>
                        {/each}
                        <td class="px-3 py-2.5 text-xs text-gray-400">{fmtDateTime(s.granted_at)}{s.granted_by_name ? ` · ${s.granted_by_name}` : ''}</td>
                        <td class="px-3 py-2.5 text-right">
                            <button type="button" onclick={() => removeStaff(s)} class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">해제</button>
                        </td>
                    </tr>
                {/each}
            </tbody>
        </table>
    </div>
    <p class="text-xs text-gray-400 mt-3">권장 구성: 교적 담당 간사는 열람·수정·내려받기, 교역자는 열람(+심방). 목장 리더에게는 주지 않습니다. 사이트 관리자도 자기에게 따로 권한을 주어야 교적을 볼 수 있습니다.</p>
{:else if view === 'access'}
    <div class="flex flex-wrap items-end gap-2 mb-4">
        <div><label for="af" class="block text-xs font-bold text-gray-600 mb-1">부터</label><input id="af" type="date" bind:value={from} class="px-3 py-2 rounded-xl border-2 border-gray-200 bg-white text-sm" /></div>
        <div><label for="at" class="block text-xs font-bold text-gray-600 mb-1">까지</label><input id="at" type="date" bind:value={to} class="px-3 py-2 rounded-xl border-2 border-gray-200 bg-white text-sm" /></div>
        <button type="button" onclick={() => loadAccess(true)} class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm">조회</button>
        <p class="text-xs text-gray-400 ml-2">누가·언제·어디서·누구의 정보를·무엇을 했는지. 3년 보관하며 아무도 고치거나 지울 수 없습니다. 이 화면을 연 것도 기록됩니다.</p>
    </div>
    <div class="rounded-2xl border border-gray-200 overflow-x-auto">
        <table class="w-full text-sm min-w-[48rem]">
            <thead class="bg-gray-50 text-xs text-gray-500">
                <tr>
                    <th class="text-left font-bold px-4 py-2">일시</th>
                    <th class="text-left font-bold px-3 py-2">처리자</th>
                    <th class="text-left font-bold px-3 py-2">작업</th>
                    <th class="text-left font-bold px-3 py-2">대상</th>
                    <th class="text-left font-bold px-3 py-2">IP</th>
                    <th class="text-left font-bold px-3 py-2">함수</th>
                </tr>
            </thead>
            <tbody>
                {#if access.length === 0}
                    <tr><td colspan="6" class="px-4 py-6 text-center text-gray-400">기록이 없습니다.</td></tr>
                {/if}
                {#each access as l (l.id)}
                    <tr class="border-t border-gray-50 align-top">
                        <td class="px-4 py-2 text-gray-500 whitespace-nowrap">{fmtDateTime(l.at)}</td>
                        <td class="px-3 py-2 text-gray-800">{l.actor_name ?? '-'}</td>
                        <td class="px-3 py-2 text-gray-800">
                            {ACTION[l.action] ?? l.action}
                            {#if l.action === 'export' && l.detail?.purpose}
                                <span class="block text-xs text-amber-700">용도: {String(l.detail.purpose)}</span>
                            {/if}
                        </td>
                        <td class="px-3 py-2 text-gray-600">
                            {l.target_count}명{#if l.target_names?.length}<span class="text-xs text-gray-400"> · {l.target_names.slice(0, 5).join(', ')}{l.target_count > 5 ? ' 외' : ''}</span>{/if}
                        </td>
                        <td class="px-3 py-2 text-xs text-gray-400 font-mono">{l.ip ?? '-'}</td>
                        <td class="px-3 py-2 text-xs text-gray-400 font-mono">{l.fn}</td>
                    </tr>
                {/each}
            </tbody>
        </table>
    </div>
    {#if accessMore}
        <div class="text-center mt-4">
            <button type="button" onclick={() => loadAccess(false)} class="px-5 py-2 rounded-xl border border-gray-200 text-sm font-bold text-gray-600 hover:bg-gray-50">더 보기</button>
        </div>
    {/if}
{:else}
    <div class="rounded-2xl border border-gray-200 overflow-x-auto">
        <table class="w-full text-sm min-w-[40rem]">
            <thead class="bg-gray-50 text-xs text-gray-500">
                <tr>
                    <th class="text-left font-bold px-4 py-2">일시</th>
                    <th class="text-left font-bold px-3 py-2">대상</th>
                    <th class="text-left font-bold px-3 py-2">작업</th>
                    <th class="text-left font-bold px-3 py-2">권한</th>
                    <th class="text-left font-bold px-3 py-2">처리자</th>
                </tr>
            </thead>
            <tbody>
                {#if perms.length === 0}
                    <tr><td colspan="5" class="px-4 py-6 text-center text-gray-400">기록이 없습니다.</td></tr>
                {/if}
                {#each perms as l (l.id)}
                    <tr class="border-t border-gray-50">
                        <td class="px-4 py-2 text-gray-500 whitespace-nowrap">{fmtDateTime(l.at)}</td>
                        <td class="px-3 py-2 text-gray-800">{l.subject_name ?? '-'}</td>
                        <td class="px-3 py-2 text-gray-800">{OP[l.op] ?? l.op}</td>
                        <td class="px-3 py-2 text-gray-600">{l.op === 'revoke' ? flags(l.old_value) : flags(l.new_value)}{l.op === 'change' ? ` (전: ${flags(l.old_value)})` : ''}</td>
                        <td class="px-3 py-2 text-gray-600">{l.actor_name ?? '시스템'}</td>
                    </tr>
                {/each}
            </tbody>
        </table>
    </div>
{/if}
