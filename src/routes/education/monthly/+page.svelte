<script lang="ts">
    import { onMount } from 'svelte';
    import { goto } from '$app/navigation';
    import { supabaseBrowser } from '$lib/supabase-browser';
    import {
        loadEducationAccess,
        DEPARTMENTS,
        MONTHLY_ROWS,
        todayISO,
        ymOf,
        isYm,
        prevYm,
        monthOnly,
        ymLabel,
        ymList,
        ymRange,
        type EducationMonthlyRow
    } from '$lib/education';
    import EducationNav from '$lib/components/EducationNav.svelte';

    type WeekRow = {
        report_date: string; department: string;
        attend: number | null; attend_online: number | null; teacher_attend: number | null;
        this_week: string | null; event_note: string | null;
    };
    type Fields = {
        // new_friends 는 <input type="number"> 바인딩이라 Svelte 가 number|null 로 넘겨준다.
        manager_name: string; new_friends: number | null;
        report_text: string; plan_text: string; suggestion: string;
    };

    let loading = $state(true);
    let denied = $state(false);
    let saving = $state(false);
    let msg = $state('');

    let ym = $state(ymOf(todayISO()));       // 회의 기준월
    const monthOptions = ymList(12);
    let printDate = $state(todayISO());       // 양식 우측 상단 날짜

    let prevWeeks = $state<WeekRow[]>([]);    // 전월 주차 (출결 + 행사 보고)
    let curWeeks = $state<WeekRow[]>([]);     // 당월 주차 (행사 계획)
    let form = $state<Record<string, Fields>>({});
    let existed = $state<Set<string>>(new Set());

    const blank = (): Fields => ({ manager_name: '', new_friends: null, report_text: '', plan_text: '', suggestion: '' });

    // ── 출결상황 (전월 평균) ─────────────────────
    // 학생 = 출석 + 온라인출석. 소수점 1자리까지 (양식과 동일하게 월 평균).
    type Att = { dept: string; student: number; teacher: number; weeks: number };
    const att = $derived.by<Att[]>(() =>
        DEPARTMENTS.map((d) => {
            const rows = prevWeeks.filter((r) => r.department === d && r.attend !== null);
            const tRows = prevWeeks.filter((r) => r.department === d && r.teacher_attend !== null);
            const avg = (arr: number[]) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0);
            return {
                dept: d,
                student: avg(rows.map((r) => (r.attend ?? 0) + (r.attend_online ?? 0))),
                teacher: avg(tRows.map((r) => r.teacher_attend ?? 0)),
                weeks: rows.length
            };
        })
    );
    const r1 = (n: number) => Math.round(n * 10) / 10;
    const show = (n: number) => (n === 0 ? '' : String(r1(n)));
    const nf = (d: string) => {
        const v = form[d]?.new_friends;
        return typeof v === 'number' && Number.isFinite(v) ? v : 0;
    };
    const rowTotal = (a: Att) => a.student + a.teacher + nf(a.dept);
    const totals = $derived.by(() => {
        const s = att.reduce((x, a) => x + a.student, 0);
        const t = att.reduce((x, a) => x + a.teacher, 0);
        const f = att.reduce((x, a) => x + nf(a.dept), 0);
        return { student: s, teacher: t, friends: f, all: s + t + f };
    });

    // ── 행사 자동 초안 ───────────────────────────
    // 주차별 '이번 주'를 줄 단위로 펼쳐 중복 제거 후 '+' 를 붙인다.
    function draft(weeks: WeekRow[], dept: string): string {
        const seen = new Set<string>();
        const lines: string[] = [];
        for (const r of weeks.filter((w) => w.department === dept)) {
            for (const raw of (r.this_week ?? '').split('\n')) {
                const s = raw.trim();
                if (!s || seen.has(s)) continue;
                seen.add(s);
                lines.push(`+${s}`);
            }
        }
        return lines.join('\n');
    }
    function fillDrafts(force = false) {
        const next = { ...form };
        for (const d of MONTHLY_ROWS) {
            const f = next[d] ?? blank();
            const rep = draft(prevWeeks, d);
            const pla = draft(curWeeks, d);
            if (force || !f.report_text.trim()) f.report_text = rep;
            if (force || !f.plan_text.trim()) f.plan_text = pla;
            next[d] = f;
        }
        form = next;
        msg = force ? '자동 초안으로 다시 채웠습니다. 저장하지 않으면 반영되지 않습니다.' : '';
    }

    async function load() {
        const prev = prevYm(ym);
        const pr = ymRange(prev);
        const cr = ymRange(ym);
        const [{ data: pw }, { data: cw }, { data: mr }, { data: carry }] = await Promise.all([
            supabaseBrowser
                .from('education_reports')
                .select('report_date, department, attend, attend_online, teacher_attend, this_week, event_note')
                .gte('report_date', pr.from).lt('report_date', pr.to)
                .order('report_date'),
            supabaseBrowser
                .from('education_reports')
                .select('report_date, department, attend, attend_online, teacher_attend, this_week, event_note')
                .gte('report_date', cr.from).lt('report_date', cr.to)
                .order('report_date'),
            supabaseBrowser.from('education_monthly_reports').select('*').eq('year_month', ym),
            // 담당자는 매달 다시 적지 않도록 가장 최근 달 값을 가져온다
            supabaseBrowser
                .from('education_monthly_reports')
                .select('department, manager_name, year_month')
                .lt('year_month', ym)
                .not('manager_name', 'is', null)
                .order('year_month', { ascending: false })
        ]);
        prevWeeks = (pw ?? []) as WeekRow[];
        curWeeks = (cw ?? []) as WeekRow[];

        const carried = new Map<string, string>();
        for (const c of (carry ?? []) as { department: string; manager_name: string }[]) {
            if (!carried.has(c.department)) carried.set(c.department, c.manager_name);
        }

        const found = new Set<string>();
        const next: Record<string, Fields> = {};
        for (const d of MONTHLY_ROWS) next[d] = blank();
        for (const r of (mr ?? []) as EducationMonthlyRow[]) {
            found.add(r.department);
            next[r.department] = {
                manager_name: r.manager_name ?? '',
                new_friends: r.new_friends,
                report_text: r.report_text ?? '',
                plan_text: r.plan_text ?? '',
                suggestion: r.suggestion ?? ''
            };
        }
        // 이번 달에 아직 없는 부서는 담당자만 이전 달에서 이어받는다
        for (const d of MONTHLY_ROWS) {
            if (!found.has(d) && carried.has(d)) next[d].manager_name = carried.get(d) ?? '';
        }
        form = next;
        existed = found;
        fillDrafts(false); // 비어 있는 칸만 초안으로 채움
    }

    onMount(async () => {
        const { hasSession, access } = await loadEducationAccess();
        if (!hasSession) return goto('/login');
        if (!access || !access.canAccess) {
            denied = true;
            loading = false;
            return;
        }
        await load();
        loading = false;
    });

    async function changeMonth(v: string) {
        if (!isYm(v)) return; // 잘못된 값이 들어와 'NaN월' 이 찍히지 않도록
        ym = v;
        loading = true;
        msg = '';
        await load();
        loading = false;
    }

    async function save() {
        saving = true;
        msg = '';
        const payload = MONTHLY_ROWS.map((d) => {
            const f = form[d];
            const txt = (s: string) => (s.trim() === '' ? null : s.trim());
            const n = f.new_friends;
            return {
                year_month: ym,
                department: d,
                manager_name: txt(f.manager_name),
                new_friends: typeof n === 'number' && Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : null,
                report_text: txt(f.report_text),
                plan_text: txt(f.plan_text),
                suggestion: txt(f.suggestion)
            };
        }).filter((p) => {
            // 전부 빈 행은 만들지 않는다 (이미 저장돼 있던 행은 비우기 허용)
            const has = p.manager_name || p.new_friends !== null || p.report_text || p.plan_text || p.suggestion;
            return has || existed.has(p.department);
        });
        if (payload.length === 0) {
            saving = false;
            msg = '입력된 내용이 없습니다.';
            return;
        }
        const { error } = await supabaseBrowser
            .from('education_monthly_reports')
            .upsert(payload, { onConflict: 'year_month,department' });
        saving = false;
        if (error) {
            msg = '저장 실패: ' + error.message;
            return;
        }
        await load();
        msg = `${ymLabel(ym)} 월간 보고서를 저장했습니다.`;
    }

    // 건의사항이 있는 행만 3번 표에 낸다 (없으면 양식처럼 빈 줄 하나)
    const suggestionRows = $derived(
        MONTHLY_ROWS.filter((d) => (form[d]?.suggestion ?? '').trim() !== '')
    );
    const fmtPrintDate = (iso: string) => iso.replaceAll('-', '.');
</script>

<svelte:head><title>교육위원회 월간 보고서 - 부평동부교회</title></svelte:head>

<div class="w-full max-w-7xl mx-auto px-6 sm:px-8 lg:px-12 py-10 sm:py-14 print:max-w-none print:p-0">
    <div class="print:hidden">
        <h1 class="text-2xl sm:text-3xl font-black text-gray-900 mb-1">교육위원회 월간 보고서</h1>
        <p class="text-gray-500 mb-6 text-sm sm:text-base">주차별 보고서를 한 달치로 모아 회의 양식으로 출력합니다.</p>

        <EducationNav />
    </div>

    {#if loading}
        <div class="py-20 text-center text-gray-400 print:hidden">불러오는 중…</div>
    {:else if denied}
        <div class="py-20 text-center print:hidden">
            <p class="text-gray-500 font-medium">접근 권한이 없습니다.</p>
            <a href="/education" class="inline-block mt-6 px-6 py-2.5 rounded-full bg-primary-900 text-white font-bold text-sm">교육부서 보고서로</a>
        </div>
    {:else}
        <!-- ===== 조작 패널 (인쇄 제외) ===== -->
        <div class="print:hidden">
            <div class="mb-5 flex flex-wrap items-end gap-3 rounded-2xl border border-gray-100 bg-gray-50 px-4 py-4">
                <div>
                    <label for="ym" class="block text-xs font-bold text-gray-600 mb-1.5">회의 기준월</label>
                    <select id="ym" value={ym} onchange={(e) => changeMonth((e.currentTarget as HTMLSelectElement).value)}
                        class="px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm">
                        {#each monthOptions as m}<option value={m}>{ymLabel(m)}</option>{/each}
                    </select>
                </div>
                <div>
                    <label for="pd" class="block text-xs font-bold text-gray-600 mb-1.5">양식 날짜</label>
                    <input id="pd" type="date" bind:value={printDate}
                        class="px-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:border-primary-500 bg-white font-medium text-sm" />
                </div>
                <button type="button" onclick={() => fillDrafts(true)}
                    class="px-4 py-2.5 rounded-xl border-2 border-gray-200 text-gray-600 font-bold text-sm hover:bg-white">행사 난 자동 초안</button>
                <button type="button" onclick={save} disabled={saving}
                    class="px-5 py-2.5 rounded-xl bg-primary-900 text-white font-bold text-sm hover:bg-primary-800 disabled:opacity-50">
                    {saving ? '저장 중…' : '저장'}
                </button>
                <button type="button" onclick={() => window.print()}
                    class="px-5 py-2.5 rounded-xl bg-gray-900 text-white font-bold text-sm hover:bg-gray-700">인쇄 / PDF 저장</button>
            </div>

            {#if msg}
                <div class="mb-5 bg-primary-50 border border-primary-100 text-primary-800 text-sm rounded-xl px-4 py-3">{msg}</div>
            {/if}

            <p class="text-xs text-gray-500 mb-3">
                출결은 <b>{monthOnly(prevYm(ym))}</b> 주차 평균(출석＋온라인)이 자동 계산되고, 행사 보고는 {monthOnly(prevYm(ym))}·계획은 {monthOnly(ym)} 주차의 '이번 주'에서 초안을 만듭니다.
                아래 표에서 직접 고칠 수 있고, <b>저장</b>해야 유지됩니다.
            </p>

            <!-- 입력 표 -->
            <div class="overflow-x-auto rounded-2xl border border-gray-300 mb-10">
                <table class="w-full text-sm border-collapse table-fixed min-w-[900px]">
                    <thead>
                        <tr class="bg-gray-50 text-gray-500 text-xs divide-x divide-gray-300 border-b border-gray-300">
                            <th class="px-3 py-2.5 text-left font-bold w-[92px]">부서</th>
                            <th class="px-3 py-2.5 text-left font-bold w-[120px]">담당자</th>
                            <th class="px-3 py-2.5 text-left font-bold w-[72px]">새친구</th>
                            <th class="px-3 py-2.5 text-left font-bold">행사 보고 ({monthOnly(prevYm(ym))})</th>
                            <th class="px-3 py-2.5 text-left font-bold">행사 계획 ({monthOnly(ym)})</th>
                            <th class="px-3 py-2.5 text-left font-bold w-[180px]">건의사항 및 비고</th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each MONTHLY_ROWS as d}
                            <tr class="border-t border-gray-200 divide-x divide-gray-200 align-top">
                                <td class="px-3 py-2.5 font-bold text-gray-900">{d}</td>
                                <td class="px-2 py-2">
                                    <input type="text" bind:value={form[d].manager_name} placeholder="예: 김주희 권사"
                                        class="w-full px-2 py-1.5 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500" />
                                </td>
                                <td class="px-2 py-2">
                                    {#if (DEPARTMENTS as readonly string[]).includes(d)}
                                        <input type="number" min="0" inputmode="numeric" bind:value={form[d].new_friends}
                                            class="w-full px-2 py-1.5 rounded-lg border border-gray-200 text-sm text-center focus:outline-none focus:border-primary-500" />
                                    {:else}
                                        <span class="text-gray-300 text-xs">—</span>
                                    {/if}
                                </td>
                                <td class="px-2 py-2">
                                    <textarea rows="3" bind:value={form[d].report_text}
                                        class="w-full px-2 py-1.5 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
                                </td>
                                <td class="px-2 py-2">
                                    <textarea rows="3" bind:value={form[d].plan_text}
                                        class="w-full px-2 py-1.5 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
                                </td>
                                <td class="px-2 py-2">
                                    <textarea rows="3" bind:value={form[d].suggestion}
                                        class="w-full px-2 py-1.5 rounded-lg border border-gray-200 text-sm focus:outline-none focus:border-primary-500 resize-y"></textarea>
                                </td>
                            </tr>
                        {/each}
                    </tbody>
                </table>
            </div>

            <h2 class="text-base font-black text-gray-900 mb-2">인쇄 미리보기</h2>
            <p class="text-xs text-gray-400 mb-3">아래 내용이 그대로 인쇄됩니다. (A4 1장 기준)</p>
        </div>

        <!-- ===== 인쇄 양식 ===== -->
        <div class="report-sheet mx-auto bg-white text-black border border-gray-300 print:border-0 p-8 print:p-0">
            <div class="relative mb-1">
                <h2 class="text-center text-2xl font-bold tracking-tight">교육위원회({monthOnly(ym)})</h2>
                <div class="text-right text-sm mt-1">{fmtPrintDate(printDate)}</div>
            </div>

            <!-- 1. 출결상황 -->
            <h3 class="text-base font-bold mt-2 mb-1">1. 출결상황</h3>
            <table class="sheet w-full">
                <thead>
                    <tr>
                        <th rowspan="2" class="w-[18%]">부 서</th>
                        <th colspan="2">학 생</th>
                        <th rowspan="2" class="w-[18%]">교 사</th>
                        <th rowspan="2" class="w-[18%]">합 계</th>
                    </tr>
                    <tr>
                        <th class="w-[23%] text-xs">학생(온라인)</th>
                        <th class="w-[18%] text-xs">새친구</th>
                    </tr>
                </thead>
                <tbody>
                    {#each att as a}
                        <tr>
                            <td class="text-left pl-2">{a.dept}</td>
                            <td>{show(a.student)}</td>
                            <td>{nf(a.dept) === 0 ? '' : nf(a.dept)}</td>
                            <td>{show(a.teacher)}</td>
                            <td>{show(rowTotal(a))}</td>
                        </tr>
                    {/each}
                    <tr><td>&nbsp;</td><td></td><td></td><td></td><td></td></tr>
                    <tr>
                        <td class="text-left pl-2">총인원</td>
                        <td>{show(totals.student)}</td>
                        <td>{totals.friends === 0 ? '' : totals.friends}</td>
                        <td>{show(totals.teacher)}</td>
                        <td>{show(totals.all)}</td>
                    </tr>
                </tbody>
            </table>

            <!-- 2. 행사보고 및 예정 -->
            <h3 class="text-base font-bold mt-4 mb-1">2. 행사보고 및 예정</h3>
            <table class="sheet w-full">
                <thead>
                    <tr>
                        <th class="w-[18%]">부 서</th>
                        <th class="w-[41%]">행사 보고({monthOnly(prevYm(ym))})</th>
                        <th class="w-[41%]">행사 계획({monthOnly(ym)})</th>
                    </tr>
                </thead>
                <tbody>
                    {#each MONTHLY_ROWS as d}
                        <tr>
                            <td class="text-center leading-tight">
                                {d}
                                {#if form[d].manager_name.trim()}<br /><span class="text-xs">({form[d].manager_name.trim()})</span>{/if}
                            </td>
                            <td class="text-left align-top pl-2 whitespace-pre-wrap break-words text-xs">{form[d].report_text}</td>
                            <td class="text-left align-top pl-2 whitespace-pre-wrap break-words text-xs">{form[d].plan_text}</td>
                        </tr>
                    {/each}
                </tbody>
            </table>

            <!-- 3. 건의사항 및 기타 -->
            <h3 class="text-base font-bold mt-4 mb-1">3. 건의사항 및 기타</h3>
            <table class="sheet w-full">
                <thead>
                    <tr>
                        <th class="w-[18%]">부 서</th>
                        <th>건의사항 및 비고</th>
                    </tr>
                </thead>
                <tbody>
                    {#if suggestionRows.length === 0}
                        <tr><td>&nbsp;</td><td></td></tr>
                    {:else}
                        {#each suggestionRows as d}
                            <tr>
                                <td class="text-center">{d}</td>
                                <td class="text-left align-top pl-2 whitespace-pre-wrap break-words text-xs">{form[d].suggestion}</td>
                            </tr>
                        {/each}
                    {/if}
                </tbody>
            </table>
        </div>
    {/if}
</div>

<style>
    @page {
        size: A4 portrait;
        margin: 14mm 12mm;
    }

    /* 양식 표: 검은 실선 · 가운데 정렬 (원본 PDF 스타일) */
    .report-sheet {
        width: 210mm;
        max-width: 100%;
    }
    .report-sheet :global(table.sheet) {
        border-collapse: collapse;
    }
    .report-sheet :global(table.sheet th),
    .report-sheet :global(table.sheet td) {
        border: 1px solid #000;
        padding: 3px 4px;
        text-align: center;
        vertical-align: middle;
        font-size: 12px;
        line-height: 1.35;
    }
    .report-sheet :global(table.sheet th) {
        font-weight: 700;
    }
    /* 표가 페이지 경계에서 잘리지 않도록 */
    .report-sheet :global(table.sheet tr) {
        break-inside: avoid;
    }

    @media print {
        /* 사이트 헤더·푸터와 레이아웃 여백을 걷어내고 양식만 남긴다 */
        :global(header),
        :global(footer),
        :global(.fixed) {
            display: none !important;
        }
        :global(body) {
            background: #fff;
        }
        /* 레이아웃 여백은 +layout.svelte 의 print:pt-0 / print:min-h-0 이 처리한다 */
        .report-sheet {
            width: auto;
            border: 0;
        }
    }
</style>
