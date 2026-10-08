<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import { fetchAll, todayISO } from '$lib/attendance';
    import { toCsv, downloadCsv, stamp, type Col } from '$lib/csv';

    // PostgREST 의 to-one 임베드는 런타임엔 객체 하나지만 생성 타입은 배열로 추론된다.
    type Embed<T> = T | T[] | null;
    const one = <T,>(v: Embed<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : (v ?? null));

    type Kind =
        | 'attendance'      // 출석 기록 (주차 × 인원)
        | 'attendance_sum'  // 출석 요약 (주차 × 소그룹)
        | 'notes'           // 특이사항 · 기타 의견
        | 'education'       // 교육부서 주간 보고서
        | 'education_month'; // 교육위원회 월간 보고서

    // area: 이 자료가 속한 권한 영역. export_users 에 지정된 영역만 받을 수 있다.
    type Area = 'attendance' | 'education';
    const KINDS: { key: Kind; name: string; desc: string; area: Area }[] = [
        { key: 'attendance', name: '출석 기록', desc: '주차 × 인원 단위. 누가 언제 출석했는지', area: 'attendance' },
        { key: 'attendance_sum', name: '출석 요약', desc: '주차 × 소그룹 단위. 인원·출석·출석률', area: 'attendance' },
        { key: 'notes', name: '특이사항 · 기타 의견', desc: '구성원 메모와 소그룹 기타 의견', area: 'attendance' },
        { key: 'education', name: '교육부서 주간 보고서', desc: '주차 × 부서. 출석현황과 교육·행사', area: 'education' },
        { key: 'education_month', name: '교육위원회 월간 보고서', desc: '월 × 부서. 담당자·새친구·행사', area: 'education' }
    ];

    type Profile = { id: string; name: string | null; office: string | null; phone: string | null; active?: boolean };
    type ExportUser = {
        user_id: string; can_attendance: boolean; can_education: boolean; note: string | null;
        custom_users: Embed<{ name: string | null; office: string | null }>;
    };

    let loading = $state(true);
    let denied = $state(false);
    let busy = $state('');
    let msg = $state('');
    let errorMsg = $state('');

    let isAdmin = $state(false);
    let canAttendance = $state(false);
    let canEducation = $state(false);

    let kind = $state<Kind>('attendance');
    let from = $state('');
    let to = $state(todayISO());

    // 지정 관리 (관리자만)
    let users = $state<ExportUser[]>([]);
    let pickerOpen = $state(false);
    let pickerQuery = $state('');
    let pickerResults = $state<Profile[]>([]);

    // 내가 받을 수 있는 자료만 보여준다.
    const kinds = $derived(
        KINDS.filter((k) => (k.area === 'attendance' ? canAttendance : canEducation))
    );

    async function loadUsers() {
        const { data } = await supabaseBrowser
            .from('export_users')
            .select('user_id, can_attendance, can_education, note, custom_users(name, office)');
        users = (data ?? []) as unknown as ExportUser[];
    }

    onMount(async () => {
        const {
            data: { session }
        } = await supabaseBrowser.auth.getSession();
        if (!session) return goto('/login');
        const { data: me } = await supabaseBrowser
            .from('custom_users')
            .select('id, roles(level)')
            .eq('auth_id', session.user.id)
            .single();
        const level = (me?.roles as unknown as { level: number } | null)?.level ?? 0;
        isAdmin = level >= 100;

        if (isAdmin) {
            canAttendance = true;
            canEducation = true;
            await loadUsers();
        } else if (me?.id) {
            // export_users RLS: 본인 행만 조회됨
            const { data: row } = await supabaseBrowser
                .from('export_users')
                .select('can_attendance, can_education')
                .eq('user_id', me.id)
                .maybeSingle();
            canAttendance = row?.can_attendance ?? false;
            canEducation = row?.can_education ?? false;
        }

        if (!canAttendance && !canEducation) {
            denied = true;
            loading = false;
            return;
        }
        // 받을 수 있는 자료 중 첫 번째를 기본 선택
        kind = kinds[0]?.key ?? 'attendance';
        // 기본 범위: 올해 1월 1일 ~ 오늘
        from = `${todayISO().slice(0, 4)}-01-01`;
        loading = false;
    });

    const valid = $derived(!!from && !!to && from <= to);

    async function searchProfiles(term: string) {
        const t = term.trim();
        if (!t) {
            pickerResults = [];
            return;
        }
        const { data } = await supabaseBrowser
            .from('custom_users')
            .select('id, name, office, phone, active')
            .ilike('name', `%${t}%`)
            .order('active', { ascending: false })
            .order('name')
            .limit(30);
        pickerResults = (data ?? []) as Profile[];
    }
    async function addUser(pid: string, area: Area) {
        const { error } = await supabaseBrowser.from('export_users').upsert(
            {
                user_id: pid,
                can_attendance: area === 'attendance',
                can_education: area === 'education'
            },
            { onConflict: 'user_id' }
        );
        msg = error ? '지정 실패 (관리자만 가능)' : '내보내기 권한을 지정했습니다.';
        pickerOpen = false;
        pickerQuery = '';
        pickerResults = [];
        await loadUsers();
    }
    /** 영역 하나를 켜고 끈다. 둘 다 꺼지면 행을 지운다(CHECK 제약). */
    async function toggleArea(u: ExportUser, area: Area) {
        const next = {
            can_attendance: area === 'attendance' ? !u.can_attendance : u.can_attendance,
            can_education: area === 'education' ? !u.can_education : u.can_education
        };
        const { error } = next.can_attendance || next.can_education
            ? await supabaseBrowser.from('export_users').update(next).eq('user_id', u.user_id)
            : await supabaseBrowser.from('export_users').delete().eq('user_id', u.user_id);
        if (error) msg = '변경 실패 (관리자만 가능)';
        await loadUsers();
    }
    async function removeUser(pid: string) {
        const { error } = await supabaseBrowser.from('export_users').delete().eq('user_id', pid);
        if (error) msg = '해제 실패 (관리자만 가능)';
        await loadUsers();
    }

    async function run() {
        if (!valid || busy) return;
        // 권한 밖 자료는 만들지 않는다 (목록에서도 숨기지만 한 번 더 막는다)
        if (!kinds.some((k) => k.key === kind)) {
            errorMsg = '이 자료를 내보낼 권한이 없습니다.';
            return;
        }
        busy = kind;
        msg = '';
        errorMsg = '';
        try {
            const k = KINDS.find((x) => x.key === kind)!;
            const { rows, name } = await build(kind);
            if (rows === 0) {
                errorMsg = `${k.name}: 해당 기간에 자료가 없습니다.`;
                return;
            }
            msg = `${k.name} ${rows}행을 내려받았습니다. (${name})`;
        } catch (e) {
            errorMsg = '내보내기에 실패했습니다: ' + (e instanceof Error ? e.message : String(e));
        } finally {
            busy = '';
        }
    }

    function save<T>(base: string, rows: T[], cols: Col<T>[]) {
        const name = `${base}_${stamp(from)}-${stamp(to)}.csv`;
        if (rows.length) downloadCsv(name, toCsv(rows, cols));
        return { rows: rows.length, name };
    }

    async function build(k: Kind): Promise<{ rows: number; name: string }> {
        if (k === 'attendance') {
            type R = {
                present: boolean;
                attendance_sessions: Embed<{ session_date: string }>;
                small_groups: Embed<{ name: string; communities: Embed<{ name: string }> }>;
                small_group_members: Embed<{ role: string; custom_users: Embed<{ name: string; office: string }> }>;
            };
            const data = await fetchAll<R>((f, t) =>
                supabaseBrowser
                    .from('attendance_records')
                    .select(
                        'present, attendance_sessions!inner(session_date), small_groups(name, communities(name)), small_group_members(role, custom_users(name, office))'
                    )
                    .gte('attendance_sessions.session_date', from)
                    .lte('attendance_sessions.session_date', to)
                    .order('id')
                    .range(f, t)
            );
            const rows = data
                .map((r) => {
                    const g = one(r.small_groups);
                    const m = one(r.small_group_members);
                    return {
                        date: one(r.attendance_sessions)?.session_date ?? '',
                        community: one(g?.communities ?? null)?.name ?? '',
                        group: g?.name ?? '',
                        name: one(m?.custom_users ?? null)?.name ?? '',
                        office: one(m?.custom_users ?? null)?.office ?? '',
                        role: m?.role === 'leader' ? '리더' : '',
                        present: r.present ? 'O' : ''
                    };
                })
                .sort((a, b) => a.date.localeCompare(b.date) || a.group.localeCompare(b.group, 'ko') || a.name.localeCompare(b.name, 'ko'));
            return save('출석기록', rows, [
                { key: 'date', label: '날짜', get: (r) => r.date },
                { key: 'community', label: '공동체', get: (r) => r.community },
                { key: 'group', label: '소그룹', get: (r) => r.group },
                { key: 'name', label: '이름', get: (r) => r.name },
                { key: 'office', label: '직분', get: (r) => r.office },
                { key: 'role', label: '역할', get: (r) => r.role },
                { key: 'present', label: '출석', get: (r) => r.present }
            ]);
        }

        if (k === 'attendance_sum') {
            // 주차 × 소그룹 집계. 분모(인원)는 현재 명단 기준이라 과거 주차는 참고값이다.
            const [{ data: ss }, { data: gs }, recs, { data: ms }] = await Promise.all([
                supabaseBrowser
                    .from('attendance_sessions')
                    .select('id, session_date')
                    .eq('active', true)
                    .gte('session_date', from)
                    .lte('session_date', to)
                    .order('session_date'),
                supabaseBrowser
                    .from('small_groups')
                    .select('id, name, sort_order, counts_in_total, communities(name, sort_order)')
                    .eq('active', true),
                fetchAll<{ session_id: number; small_group_id: number; present: boolean }>((f, t) =>
                    supabaseBrowser
                        .from('attendance_records')
                        .select('session_id, small_group_id, present')
                        .order('id')
                        .range(f, t)
                ),
                supabaseBrowser.from('small_group_members').select('small_group_id, active, role')
            ]);
            const sessions = (ss ?? []) as { id: number; session_date: string }[];
            const groups = (gs ?? []) as unknown as {
                id: number; name: string; sort_order: number; counts_in_total: boolean;
                communities: Embed<{ name: string; sort_order: number }>;
            }[];
            const sessionIds = new Set(sessions.map((s) => s.id));
            const members = (ms ?? []) as { small_group_id: number; active: boolean; role: string }[];

            const size = new Map<number, number>();
            for (const g of groups) {
                size.set(
                    g.id,
                    members.filter(
                        (m) => m.small_group_id === g.id && m.active && (g.counts_in_total || m.role !== 'leader')
                    ).length
                );
            }
            const presentBy = new Map<string, number>();
            for (const r of recs) {
                if (!r.present || !sessionIds.has(r.session_id)) continue;
                const key = `${r.session_id}:${r.small_group_id}`;
                presentBy.set(key, (presentBy.get(key) ?? 0) + 1);
            }
            const rows: { date: string; community: string; group: string; members: number; present: number; rate: string }[] = [];
            for (const s of sessions) {
                for (const g of groups) {
                    const p = presentBy.get(`${s.id}:${g.id}`) ?? 0;
                    const n = size.get(g.id) ?? 0;
                    if (p === 0 && n === 0) continue;
                    rows.push({
                        date: s.session_date,
                        community: one(g.communities)?.name ?? '',
                        group: g.name,
                        members: n,
                        present: p,
                        rate: n > 0 ? String(Math.round((100 * p) / n)) : ''
                    });
                }
            }
            return save('출석요약', rows, [
                { key: 'date', label: '날짜', get: (r) => r.date },
                { key: 'community', label: '공동체', get: (r) => r.community },
                { key: 'group', label: '소그룹', get: (r) => r.group },
                { key: 'members', label: '인원', get: (r) => r.members },
                { key: 'present', label: '출석', get: (r) => r.present },
                { key: 'rate', label: '출석률(%)', get: (r) => r.rate }
            ]);
        }

        if (k === 'notes') {
            type MN = {
                note: string;
                attendance_sessions: Embed<{ session_date: string }>;
                small_groups: Embed<{ name: string; communities: Embed<{ name: string }> }>;
                small_group_members: Embed<{ custom_users: Embed<{ name: string; office: string }> }>;
            };
            type GN = {
                note: string;
                attendance_sessions: Embed<{ session_date: string }>;
                small_groups: Embed<{ name: string; communities: Embed<{ name: string }> }>;
            };
            const [mn, gn] = await Promise.all([
                fetchAll<MN>((f, t) =>
                    supabaseBrowser
                        .from('member_notes')
                        .select(
                            'note, attendance_sessions!inner(session_date), small_groups(name, communities(name)), small_group_members(custom_users(name, office))'
                        )
                        .gte('attendance_sessions.session_date', from)
                        .lte('attendance_sessions.session_date', to)
                        .order('id')
                        .range(f, t)
                ),
                fetchAll<GN>((f, t) =>
                    supabaseBrowser
                        .from('group_session_notes')
                        .select('note, attendance_sessions!inner(session_date), small_groups(name, communities(name))')
                        .gte('attendance_sessions.session_date', from)
                        .lte('attendance_sessions.session_date', to)
                        .order('id')
                        .range(f, t)
                )
            ]);
            const rows = [
                ...mn.map((r) => {
                    const g = one(r.small_groups);
                    const u = one(one(r.small_group_members)?.custom_users ?? null);
                    return {
                        date: one(r.attendance_sessions)?.session_date ?? '',
                        community: one(g?.communities ?? null)?.name ?? '',
                        group: g?.name ?? '',
                        type: '특이사항',
                        name: u?.name ?? '',
                        office: u?.office ?? '',
                        note: r.note
                    };
                }),
                ...gn.map((r) => {
                    const g = one(r.small_groups);
                    return {
                        date: one(r.attendance_sessions)?.session_date ?? '',
                        community: one(g?.communities ?? null)?.name ?? '',
                        group: g?.name ?? '',
                        type: '기타 의견',
                        name: '',
                        office: '',
                        note: r.note
                    };
                })
            ].sort((a, b) => a.date.localeCompare(b.date) || a.group.localeCompare(b.group, 'ko'));
            return save('특이사항', rows, [
                { key: 'date', label: '날짜', get: (r) => r.date },
                { key: 'community', label: '공동체', get: (r) => r.community },
                { key: 'group', label: '소그룹', get: (r) => r.group },
                { key: 'type', label: '구분', get: (r) => r.type },
                { key: 'name', label: '대상자', get: (r) => r.name },
                { key: 'office', label: '직분', get: (r) => r.office },
                { key: 'note', label: '내용', get: (r) => r.note }
            ]);
        }

        if (k === 'education') {
            type R = {
                report_date: string; department: string;
                enrolled: number | null; attend: number | null; attend_online: number | null;
                teacher_enrolled: number | null; teacher_attend: number | null;
                attendance_note: string | null; this_week: string | null; next_week: string | null; event_note: string | null;
            };
            const data = await fetchAll<R>((f, t) =>
                supabaseBrowser
                    .from('education_reports')
                    .select('*')
                    .gte('report_date', from)
                    .lte('report_date', to)
                    .order('report_date')
                    .range(f, t)
            );
            return save('교육부서_주간보고서', data, [
                { key: 'report_date', label: '날짜', get: (r) => r.report_date },
                { key: 'department', label: '부서', get: (r) => r.department },
                { key: 'enrolled', label: '재적', get: (r) => r.enrolled },
                { key: 'attend', label: '출석', get: (r) => r.attend },
                { key: 'attend_online', label: '출석(온라인)', get: (r) => r.attend_online },
                { key: 'teacher_enrolled', label: '교사재적', get: (r) => r.teacher_enrolled },
                { key: 'teacher_attend', label: '교사출석', get: (r) => r.teacher_attend },
                { key: 'attendance_note', label: '비고 및 새가족', get: (r) => r.attendance_note },
                { key: 'this_week', label: '이번 주', get: (r) => r.this_week },
                { key: 'next_week', label: '다음 주', get: (r) => r.next_week },
                { key: 'event_note', label: '비고 및 건의사항', get: (r) => r.event_note }
            ]);
        }

        // education_month — year_month 는 'YYYY-MM' 이라 날짜 범위를 월로 잘라 비교한다.
        type MR = {
            year_month: string; department: string; manager_name: string | null;
            new_friends: number | null; report_text: string | null; plan_text: string | null; suggestion: string | null;
        };
        const { data } = await supabaseBrowser
            .from('education_monthly_reports')
            .select('*')
            .gte('year_month', from.slice(0, 7))
            .lte('year_month', to.slice(0, 7))
            .order('year_month');
        const rows = (data ?? []) as MR[];
        return save('교육위원회_월간보고서', rows, [
            { key: 'year_month', label: '월', get: (r) => r.year_month },
            { key: 'department', label: '부서', get: (r) => r.department },
            { key: 'manager_name', label: '담당자', get: (r) => r.manager_name },
            { key: 'new_friends', label: '새친구', get: (r) => r.new_friends },
            { key: 'report_text', label: '행사 보고', get: (r) => r.report_text },
            { key: 'plan_text', label: '행사 계획', get: (r) => r.plan_text },
            { key: 'suggestion', label: '건의사항 및 비고', get: (r) => r.suggestion }
        ]);
    }

    function preset(kind: 'year' | 'half' | 'month') {
        const t = todayISO();
        const [y, m] = t.split('-').map(Number);
        to = t;
        if (kind === 'year') from = `${y}-01-01`;
        else if (kind === 'half') from = m <= 6 ? `${y}-01-01` : `${y}-07-01`;
        else from = `${y}-${String(m).padStart(2, '0')}-01`;
    }
</script>

<svelte:head><title>자료 내보내기 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14">
    <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">자료 내보내기</h1>
    <p class="text-gray-500 mb-6 text-sm sm:text-base">출석부·교육부서 자료를 기간을 정해 CSV 로 내려받습니다.</p>

    {#if loading}
        <div class="py-20 text-center text-gray-400">불러오는 중…</div>
    {:else if denied}
        <div class="py-20 text-center">
            <p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
            <p class="text-gray-400 text-sm mt-2">관리자가 지정한 사람만 사용할 수 있습니다.</p>
            <a href="/" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">홈으로</a>
        </div>
    {:else}
        <div class="mb-6 rounded-2xl border border-amber-100 bg-amber-50 px-4 py-3 text-sm text-amber-900">
            내려받은 파일에는 <b>이름·직분·특이사항 등 개인정보</b>가 담깁니다. 보관·공유에 주의해 주세요.
        </div>

        <!-- 기간 -->
        <div class="rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4 mb-5">
            <div class="flex flex-wrap items-end gap-3">
                <div>
                    <label for="from" class="block text-xs font-bold text-gray-600 mb-1.5">시작일</label>
                    <input id="from" type="date" bind:value={from}
                        class="px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm" />
                </div>
                <div>
                    <label for="to" class="block text-xs font-bold text-gray-600 mb-1.5">종료일</label>
                    <input id="to" type="date" bind:value={to}
                        class="px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm" />
                </div>
                <div class="flex gap-1.5">
                    <button type="button" onclick={() => preset('month')} class="px-3 py-2 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-xs hover:bg-white">이번 달</button>
                    <button type="button" onclick={() => preset('half')} class="px-3 py-2 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-xs hover:bg-white">이번 반기</button>
                    <button type="button" onclick={() => preset('year')} class="px-3 py-2 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-xs hover:bg-white">올해</button>
                </div>
            </div>
            {#if !valid}
                <p class="mt-2 text-xs font-bold text-red-500">시작일이 종료일보다 늦습니다.</p>
            {/if}
        </div>

        {#if msg}
            <div class="mb-5 bg-green-50 border border-green-100 text-green-700 text-sm rounded-xl px-4 py-3">{msg}</div>
        {/if}
        {#if errorMsg}
            <div class="mb-5 bg-red-50 border border-red-100 text-red-600 text-sm rounded-xl px-4 py-3">{errorMsg}</div>
        {/if}

        <!-- 자료 선택 -->
        <div class="rounded-2xl border border-gray-200 overflow-hidden mb-6">
            {#each kinds as k}
                <label class="flex items-start gap-3 px-4 py-3 border-b border-gray-50 last:border-0 cursor-pointer hover:bg-gray-50">
                    <input type="radio" name="kind" value={k.key} bind:group={kind} class="mt-1" />
                    <span>
                        <span class="font-bold text-gray-900">{k.name}</span>
                        <span class="block text-xs text-gray-500">{k.desc}</span>
                    </span>
                </label>
            {/each}
        </div>

        <button type="button" onclick={run} disabled={!valid || !!busy}
            class="px-6 py-3 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-40">
            {busy ? '만드는 중…' : 'CSV 내려받기'}
        </button>

        <p class="mt-4 text-xs text-gray-400">
            ※ 엑셀에서 바로 열립니다. '출석 요약'의 인원은 <b>현재 명단</b> 기준이라 과거 주차는 참고값입니다.
        </p>

        <!-- 내보내기 권한 지정 (관리자만) -->
        {#if isAdmin}
            <section class="mt-14">
                <div class="flex items-center justify-between mb-3">
                    <h2 class="text-lg font-black text-gray-900">내보내기 권한 지정</h2>
                    <button type="button" onclick={() => { pickerOpen = !pickerOpen; pickerQuery = ''; pickerResults = []; }}
                        class="px-4 py-2 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">+ 사람 추가</button>
                </div>
                <p class="text-xs text-gray-400 mb-3">
                    지정된 사람은 해당 영역의 자료를 <b>개인정보가 담긴 파일로</b> 내려받을 수 있습니다. (지정/해제는 관리자만 가능)
                </p>

                {#if pickerOpen}
                    <div class="rounded-2xl border border-gray-200 p-4 mb-4 bg-gray-50">
                        <input type="text" placeholder="이름으로 검색" bind:value={pickerQuery} oninput={() => searchProfiles(pickerQuery)}
                            class="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 mb-2" />
                        <div class="max-h-56 overflow-y-auto divide-y divide-gray-100 bg-white rounded-lg">
                            {#each pickerResults as r}
                                <div class="flex items-center gap-2 px-3 py-2 text-sm">
                                    <span class="font-medium flex-1 min-w-0 truncate">
                                        {r.name}{#if r.active === false}<span class="ml-1 text-[10px] text-gray-400 font-normal">(미가입)</span>{/if}
                                        <span class="text-gray-400 text-xs ml-1">{r.office ?? ''}</span>
                                    </span>
                                    <button type="button" onclick={() => addUser(r.id, 'attendance')}
                                        class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:border-primary-400 hover:text-primary-700 shrink-0">출석</button>
                                    <button type="button" onclick={() => addUser(r.id, 'education')}
                                        class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-gray-200 text-gray-600 hover:border-primary-400 hover:text-primary-700 shrink-0">교육</button>
                                </div>
                            {/each}
                            {#if pickerQuery && pickerResults.length === 0}<div class="px-3 py-3 text-sm text-gray-400">검색 결과 없음</div>{/if}
                        </div>
                    </div>
                {/if}

                <div class="rounded-2xl border border-gray-100 overflow-hidden">
                    {#if users.length === 0}
                        <div class="px-4 py-5 text-sm text-gray-400 text-center">
                            지정된 사람이 없습니다. (관리자는 지정 없이도 전체를 내보낼 수 있습니다)
                        </div>
                    {/if}
                    {#each users as u (u.user_id)}
                        {@const o = one(u.custom_users)}
                        <div class="flex items-center gap-2 px-4 py-3 border-b border-gray-50 last:border-0 flex-wrap">
                            <div class="flex-1 min-w-0">
                                <span class="font-bold text-gray-900">{o?.name ?? '(이름없음)'}</span>
                                <span class="text-xs text-gray-400 ml-2">{o?.office ?? ''}{u.note ? ` · ${u.note}` : ''}</span>
                            </div>
                            <button type="button" onclick={() => toggleArea(u, 'attendance')}
                                class="px-2.5 py-1.5 rounded-lg text-xs font-bold border {u.can_attendance ? 'bg-primary-900 text-white border-primary-900' : 'border-gray-200 text-gray-400'}">출석</button>
                            <button type="button" onclick={() => toggleArea(u, 'education')}
                                class="px-2.5 py-1.5 rounded-lg text-xs font-bold border {u.can_education ? 'bg-primary-900 text-white border-primary-900' : 'border-gray-200 text-gray-400'}">교육</button>
                            <button type="button" onclick={() => removeUser(u.user_id)}
                                class="px-2.5 py-1.5 rounded-lg text-xs font-bold border border-red-200 text-red-500 hover:bg-red-50">해제</button>
                        </div>
                    {/each}
                </div>
            </section>
        {/if}
    {/if}
</div>
