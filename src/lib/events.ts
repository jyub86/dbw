// 교회 일정(church_events) — KST 기준 날짜 유틸 & 반복 전개

export type ChurchEvent = {
    id: string;
    title: string;
    description: string | null;
    start_date: string; // timestamptz ISO
    end_date: string;
    is_all_day: boolean;
    location: string | null;
    recurrence_type: 'none' | 'weekly' | 'monthly' | 'yearly' | string;
    recurrence_end_date: string | null;
    day_of_week: number | null; // 1=일 … 7=토
    day_of_month: number | null;
    month_of_year: number | null;
};

export type Occurrence = { date: string; event: ChurchEvent }; // date: 'YYYY-MM-DD' (KST)

const TZ = 'Asia/Seoul';

/** timestamptz → KST 'YYYY-MM-DD' */
export function kstDate(iso: string): string {
    return new Date(iso).toLocaleDateString('en-CA', { timeZone: TZ });
}
/** timestamptz → KST 'HH:MM' (24h) */
export function kstTime(iso: string): string {
    return new Date(iso).toLocaleTimeString('en-GB', {
        timeZone: TZ,
        hour: '2-digit',
        minute: '2-digit'
    });
}
/** KST 기준 오늘 'YYYY-MM-DD' */
export function todayKST(): string {
    return new Date().toLocaleDateString('en-CA', { timeZone: TZ });
}

// ── 날짜 문자열 연산 (타임존 무관, UTC 기준 계산) ──
function parse(s: string) {
    const [y, m, d] = s.split('-').map(Number);
    return { y, m, d };
}
function fmt(y: number, m: number, d: number) {
    return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}
export function addDays(s: string, n: number): string {
    const { y, m, d } = parse(s);
    const dt = new Date(Date.UTC(y, m - 1, d));
    dt.setUTCDate(dt.getUTCDate() + n);
    return dt.toISOString().slice(0, 10);
}
/** n개월 후 같은 일자. 해당 월에 그 일자가 없으면 null */
function addMonths(s: string, n: number): string | null {
    const { y, m, d } = parse(s);
    const total = (m - 1) + n;
    const ty = y + Math.floor(total / 12);
    const tm = ((total % 12) + 12) % 12; // 0-based
    const dt = new Date(Date.UTC(ty, tm, d));
    if (dt.getUTCMonth() !== tm) return null; // 일자 넘침(예: 2/30)
    return dt.toISOString().slice(0, 10);
}
function addYears(s: string, n: number): string | null {
    const { y, m, d } = parse(s);
    const dt = new Date(Date.UTC(y + n, m - 1, d));
    if (dt.getUTCMonth() !== m - 1) return null; // 윤년 2/29
    return dt.toISOString().slice(0, 10);
}
/** 'YYYY-MM-DD'의 요일 1=일 … 7=토 */
export function weekdayOf(s: string): number {
    const { y, m, d } = parse(s);
    return new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 1;
}

/** 한 이벤트를 [rangeStart, rangeEnd](KST 날짜 문자열) 범위 내 발생일들로 전개 */
export function expandEvent(ev: ChurchEvent, rangeStart: string, rangeEnd: string): Occurrence[] {
    const startD = kstDate(ev.start_date);
    const out: Occurrence[] = [];

    if (ev.recurrence_type === 'none' || !ev.recurrence_type) {
        // 비반복: 시작~종료 KST 날짜 구간을 채움 (대부분 당일)
        const endD = kstDate(ev.end_date);
        let d = startD < rangeStart ? rangeStart : startD;
        const last = endD > rangeEnd ? rangeEnd : endD;
        let guard = 0;
        while (d <= last && guard++ < 400) {
            if (d >= startD && d <= endD) out.push({ date: d, event: ev });
            d = addDays(d, 1);
        }
        return out;
    }

    const recEnd = ev.recurrence_end_date ? kstDate(ev.recurrence_end_date) : null;
    const hardEnd = recEnd && recEnd < rangeEnd ? recEnd : rangeEnd;

    let d: string | null = startD;
    let guard = 0;
    while (d && d <= hardEnd && guard++ < 1000) {
        if (d >= rangeStart) out.push({ date: d, event: ev });
        if (ev.recurrence_type === 'weekly') d = addDays(d, 7);
        else if (ev.recurrence_type === 'monthly') d = addMonths(d, 1);
        else if (ev.recurrence_type === 'yearly') d = addYears(d, 1);
        else if (ev.recurrence_type === 'daily') d = addDays(d, 1);
        else break;
    }
    return out;
}

/** 월(year, month 1-12)의 6주 그리드 시작/끝(일요일 시작) KST 날짜 */
export function monthGridRange(year: number, month: number) {
    const first = fmt(year, month, 1);
    const gridStart = addDays(first, -(weekdayOf(first) - 1)); // 그 주 일요일
    // 다음 달 1일
    const nextFirst = month === 12 ? fmt(year + 1, 1, 1) : fmt(year, month + 1, 1);
    const lastDay = addDays(nextFirst, -1);
    const gridEnd = addDays(lastDay, 7 - weekdayOf(lastDay)); // 그 주 토요일
    return { gridStart, gridEnd };
}

/** KST 날짜 'YYYY-MM-DD' + 'HH:MM' → timestamptz ISO (+09:00) */
export function toKstInstant(date: string, time: string): string {
    return `${date}T${time}:00+09:00`;
}

export const WEEKDAY_LABELS = ['일', '월', '화', '수', '목', '금', '토'];
