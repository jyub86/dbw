<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { call, loadCodes, codesOf, today, type Code, type RegistryMe } from '$lib/registry';

    let { me }: { me: RegistryMe } = $props();

    type Similar = { person_id: string; name: string | null; office: string | null; phone: string | null; has_account: boolean; in_registry: boolean; group_name: string | null };

    let codes = $state<Code[]>([]);
    let f = $state({
        name: '', phone: '', gender: '', birth_date: '', birth_lunar: false, registered_on: today(), office: '',
        address_zip: '', address1: '', address2: '', occupation: '', workplace: '', marital_status: '',
        previous_church: '', guide_name: '', note: ''
    });
    let consentPaper = $state(false);
    let saving = $state(false);
    let errorMsg = $state('');

    // 이미 있는 사람 (이름 또는 전화가 같은 사람)
    let similar = $state<Similar[]>([]);
    let timer: ReturnType<typeof setTimeout> | undefined;
    function checkSimilar() {
        clearTimeout(timer);
        timer = setTimeout(async () => {
            const name = f.name.trim();
            const digits = f.phone.replace(/\D/g, '');
            if (!name && digits.length < 8) return (similar = []);
            const r = await call<Similar[]>('registry_find_similar', { p_name: name || null, p_phone: digits || null });
            similar = r.ok ? r.data : [];
        }, 500);
    }

    async function enroll(pid: string) {
        const r = await call('registry_enroll', { p_person_id: pid, p_registered_on: f.registered_on || null }, '교적에 올리지 못했습니다.');
        if (!r.ok) return (errorMsg = r.error);
        goto(`/registry/${pid}`);
    }

    async function submit(e: SubmitEvent) {
        e.preventDefault();
        if (saving) return;
        if (!f.name.trim()) return (errorMsg = '이름을 넣어 주세요.');
        saving = true;
        errorMsg = '';
        const p: Record<string, unknown> = {};
        for (const [k, v] of Object.entries(f)) {
            if (typeof v === 'boolean') p[k] = v;
            else if (v.trim()) p[k] = v.trim();
        }
        const r = await call<string>('registry_register', { p }, '등록하지 못했습니다.');
        if (!r.ok) {
            saving = false;
            return (errorMsg = r.error);
        }
        const id = r.data;
        if (consentPaper) {
            await call('registry_add_consent', { p_person_id: id, p_kind: 'registry', p_granted_on: f.registered_on || null, p_method: 'paper' });
        }
        goto(`/registry/${id}`);
    }

    onMount(async () => {
        codes = await loadCodes();
    });

    const input = 'w-full px-3 py-2 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white text-sm';
    const label = 'block text-xs font-bold text-gray-600 mb-1';
</script>

<form onsubmit={submit} class="max-w-4xl space-y-6">
    <section class="rounded-2xl border border-gray-100 p-5">
        <h2 class="text-base font-black text-gray-900 mb-4">기본 정보</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div><label class={label} for="n-name">이름 *</label><input id="n-name" class={input} bind:value={f.name} oninput={checkSimilar} required /></div>
            <div><label class={label} for="n-phone">휴대전화</label><input id="n-phone" class={input} bind:value={f.phone} oninput={checkSimilar} inputmode="tel" placeholder="010-0000-0000" /></div>
            <div>
                <label class={label} for="n-gender">성별</label>
                <select id="n-gender" class={input} bind:value={f.gender}><option value="">미상</option><option value="남">남</option><option value="여">여</option></select>
            </div>
            <div>
                <label class={label} for="n-birth">생년월일</label>
                <input id="n-birth" type="date" class={input} bind:value={f.birth_date} />
                <label class="inline-flex items-center gap-1.5 mt-1.5 text-xs text-gray-600"><input type="checkbox" bind:checked={f.birth_lunar} /> 음력</label>
            </div>
            <div><label class={label} for="n-reg">등록일</label><input id="n-reg" type="date" class={input} bind:value={f.registered_on} /></div>
            <div>
                <label class={label} for="n-office">직분</label>
                <select id="n-office" class={input} bind:value={f.office}>
                    <option value="">없음 (성도)</option>
                    {#each codesOf(codes, 'office') as c}<option value={c.code}>{c.label}</option>{/each}
                </select>
            </div>
        </div>

        {#if similar.length > 0}
            <div class="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3">
                <p class="text-sm font-bold text-amber-800 mb-2">이름이나 전화번호가 같은 사람이 이미 있습니다. 같은 분이면 새로 만들지 말고 아래에서 고르세요.</p>
                <div class="divide-y divide-amber-100">
                    {#each similar as s}
                        <div class="flex flex-wrap items-center gap-x-3 gap-y-1 py-2 text-sm">
                            <b class="text-gray-900">{s.name}</b>
                            <span class="text-xs text-gray-500">{s.office ?? ''} · {s.phone ?? '번호없음'} · {s.group_name ?? '목장 없음'}{s.has_account ? ' · 앱 가입' : ''}</span>
                            {#if s.in_registry}
                                <a href={`/registry/${s.person_id}`} class="ml-auto px-3 py-1.5 rounded-lg text-xs font-bold border border-gray-200 bg-white text-gray-700">교적 보기</a>
                            {:else if me.can_edit}
                                <button type="button" onclick={() => enroll(s.person_id)} class="ml-auto px-3 py-1.5 rounded-lg text-xs font-bold bg-primary-900 text-white">이 사람을 교적에 등록</button>
                            {/if}
                        </div>
                    {/each}
                </div>
            </div>
        {/if}
    </section>

    <section class="rounded-2xl border border-gray-100 p-5">
        <h2 class="text-base font-black text-gray-900 mb-4">주소·기타</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div><label class={label} for="n-zip">우편번호</label><input id="n-zip" class={input} bind:value={f.address_zip} /></div>
            <div class="sm:col-span-2"><label class={label} for="n-a1">주소</label><input id="n-a1" class={input} bind:value={f.address1} /></div>
            <div class="sm:col-span-2 lg:col-span-3"><label class={label} for="n-a2">상세 주소</label><input id="n-a2" class={input} bind:value={f.address2} /></div>
            <div><label class={label} for="n-job">직업</label><input id="n-job" class={input} bind:value={f.occupation} /></div>
            <div><label class={label} for="n-work">직장·학교</label><input id="n-work" class={input} bind:value={f.workplace} /></div>
            <div>
                <label class={label} for="n-mar">결혼</label>
                <select id="n-mar" class={input} bind:value={f.marital_status}>
                    <option value="">미상</option>
                    {#each codesOf(codes, 'marital') as c}<option value={c.code}>{c.label}</option>{/each}
                </select>
            </div>
            <div><label class={label} for="n-prev">이전 교회</label><input id="n-prev" class={input} bind:value={f.previous_church} /></div>
            <div><label class={label} for="n-guide">인도자</label><input id="n-guide" class={input} bind:value={f.guide_name} /></div>
            <div class="sm:col-span-2 lg:col-span-3"><label class={label} for="n-note">비고</label><textarea id="n-note" rows="3" class={input} bind:value={f.note}></textarea></div>
        </div>
    </section>

    <label class="flex items-start gap-2 text-sm text-gray-700">
        <input type="checkbox" bind:checked={consentPaper} class="mt-0.5" />
        <span>새가족 등록카드의 개인정보 수집·이용 동의(서면)를 받았습니다. <span class="text-xs text-gray-400">체크하면 동의 기록이 함께 남습니다.</span></span>
    </label>

    {#if errorMsg}
        <div class="bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
    {/if}

    <div class="flex gap-2">
        <button type="submit" disabled={saving} class="px-6 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-50">등록</button>
        <a href="/registry" class="px-6 py-2.5 rounded-xl border border-gray-200 text-gray-600 font-bold text-sm hover:bg-gray-50">취소</a>
    </div>
    <p class="text-xs text-gray-400">등록하면 앱에 가입하지 않은 교인으로 만들어집니다. 나중에 이분이 같은 이름·전화번호로 앱에 가입하면 자동으로 이어집니다. 신급·세대는 등록한 뒤 교적 카드에서 넣습니다.</p>
</form>
