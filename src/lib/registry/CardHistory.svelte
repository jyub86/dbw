<script lang="ts">
    import { fmtDateTime, type Card } from '$lib/registry';

    let { card }: { card: Card } = $props();

    const TABLE: Record<string, string> = {
        'public.custom_users': '인적사항',
        'registry.people': '교적',
        'registry.status_events': '재적',
        'registry.faith_events': '신급',
        'registry.office_terms': '직분',
        'registry.notes': '메모',
        'registry.consents': '동의',
        'registry.households': '세대',
        'registry.household_members': '세대원'
    };
    const OP: Record<string, string> = {
        INSERT: '추가', UPDATE: '수정', DELETE: '삭제', MERGE: '가입 계정과 합침', UNLINK: '앱 탈퇴(연결 끊김)',
        PURGE: '인적사항 파기(5년 경과)'
    };
    // 화면에 보이는 필드 이름
    const FIELD: Record<string, string> = {
        name: '이름', phone: '전화', gender: '성별', birth_date: '생년월일', office: '호칭', member: '교인 인증',
        name_note: '동명이인 구분', birth_lunar: '음력', address_zip: '우편번호', address1: '주소', address2: '상세 주소',
        occupation: '직업', workplace: '직장', marital_status: '결혼', wedding_date: '결혼기념일', previous_church: '이전 교회',
        guide_person_id: '인도자', guide_name: '인도자', sms_opt_out: '문자 수신', faith_checked_on: '신급 확인일', note: '비고',
        updated_by: '수정자', relation: '관계', person_id: '사람', kind: '종류', event_date: '날짜', ended_on: '종료일',
        started_on: '시작일', standing: '구분', revoked_on: '철회일', household_id: '세대',
        email: '이메일', profile_picture: '사진', guardian_name: '법정대리인', purged_on: '파기일'
    };
    const fields = (f: string[] | null) => (f ?? []).filter((x) => x !== 'updated_by').map((x) => FIELD[x] ?? x).join(', ');
</script>

<p class="text-xs text-gray-400 mb-3">최근 200건입니다. 가입한 계정과 합쳐진 경우 합치기 전 기록도 함께 보입니다.</p>
{#if card.history.length === 0}
    <p class="text-sm text-gray-400">기록이 없습니다.</p>
{:else}
    <div class="rounded-2xl border border-gray-200 overflow-x-auto">
        <table class="w-full text-sm min-w-[36rem]">
            <thead class="bg-gray-50 text-xs text-gray-500">
                <tr>
                    <th class="text-left font-bold px-4 py-2">일시</th>
                    <th class="text-left font-bold px-3 py-2">처리자</th>
                    <th class="text-left font-bold px-3 py-2">항목</th>
                    <th class="text-left font-bold px-3 py-2">작업</th>
                    <th class="text-left font-bold px-3 py-2">바뀐 칸</th>
                </tr>
            </thead>
            <tbody>
                {#each card.history as h, i (i)}
                    <tr class="border-t border-gray-50">
                        <td class="px-4 py-2 text-gray-500 whitespace-nowrap">{fmtDateTime(h.at)}</td>
                        <td class="px-3 py-2 text-gray-700">{h.actor ?? '시스템'}</td>
                        <td class="px-3 py-2 text-gray-700">{TABLE[h.table] ?? h.table}</td>
                        <td class="px-3 py-2 text-gray-700">{OP[h.op] ?? h.op}</td>
                        <td class="px-3 py-2 text-gray-500">{h.op === 'UPDATE' || h.op === 'PURGE' ? fields(h.fields) : ''}</td>
                    </tr>
                {/each}
            </tbody>
        </table>
    </div>
{/if}
