# 출석 통계 집계 규칙

출석 대시보드(`/attendance/dashboard`)의 숫자는 전부 Postgres 함수에서 계산된다.
**이 함수들은 저장소에 없고 DB 에만 있다.** 수정 전에 현재 정의부터 확인할 것.

```sql
select pg_get_functiondef(oid) from pg_proc
where proname in ('att_week','att_full','att_weekly_trend','att_monthly_trend');
```

| 함수 | 용도 |
|---|---|
| `att_week(p_session_id)` | 주차별 |
| `att_full(p_community_id)` | 전체 누적 |
| `att_weekly_trend(p_weeks, p_community_id, p_group_id)` | 주간 추이 |
| `att_monthly_trend(p_community_id, p_group_id)` | 월별 추이 |

넷 다 `SECURITY DEFINER` + `app_can_view_stats()` 가드이며 jsonb 를 돌려준다.

## 규칙 1 — 합계에서 빠지는 소그룹

`small_groups.counts_in_total = false` 인 그룹(현재 '자녀돌봄')은 공동체·전체 합계와
출석률에서 제외하고, 출석 인원만 `side_present` / `side_members` 로 따로 내려보낸다.
`groups` 배열에는 그대로 넣되 `counts` 플래그를 붙여 UI 가 '집계 제외' 배지를 달 수 있게 한다.

추이에서는 아예 빠지지만, 그 그룹을 직접 선택(`p_group_id`)하면 볼 수 있다.

## 규칙 2 — 합계 제외 그룹의 리더는 인원에서 뺀다

자녀돌봄의 인솔 리더는 '자녀 수'가 아니므로 재적·출석 양쪽에서 제외한다.
리더는 보통 본인 소속 소그룹에서 이미 잡히므로 누락되지 않는다.
**일반 그룹은 종전대로 리더도 인원에 포함한다.**

DB 의 리더 지정(`small_group_members.role`)은 지우면 안 된다. RLS 가 이 값으로 그룹 접근
권한을 판정하므로, 출석 체크 화면에서는 *화면에서만* 리더를 걸러낸다.

## 규칙 3 — 제외된 인원의 과거 출석 (2026-09-04)

`small_group_members.active = false`('제외됨')는 탈퇴가 아니라 *그 소그룹 명단에서만* 뺀 상태다.
프로필·출석기록·메모는 모두 남고 '복귀' 버튼으로 되돌아간다.

과거에는 제외 시 재적에서는 빠지는데 과거 출석 기록은 계속 분자에 잡혀서
**출석률이 100% 를 넘었다**(로뎀나무숲 110%). 출석 기록은 '과거 사실'이고 `active` 는
'현재 사실'인데 한 분수에 넣은 것이 원인이었다.

지금은 `mem` 조인 조건에 아래를 넣어 해결한다.

```sql
and (m.active or exists (
      select 1 from attendance_records a
      where a.member_id = m.id and a.session_id in (해당 기간의 세션)))
```

"그 기간에 출석 기록이 있으면 그때 명단에 있었다"고 보고 분모에 포함한다.
출석자는 반드시 분모에 들어가므로 **100% 초과가 구조적으로 불가능**하다.

- 한계: 제외된 사람이 **결석**한 주는 분모에 안 잡혀 그 주 출석률이 다소 관대해진다.

## 보류 중 — 가입/이탈 기간 이력

위 한계까지 없애려면 시점별 재적이 필요하지만 지금 규모(제외 1명)에는 과하다고 보고 보류했다.

**지금 하지 않는 이유**

1. `joined_at` 이 실제 합류일이 아니다. 504명이 전부 `2026-06-22`(엑셀 임포트 시각)라
   `left_at` 만 추가해도 "언제 들어왔나"는 여전히 부정확하다.
2. `att_full` 이 `sum(present) / sum(members * recorded)` 구조라 시점별 재적을 넣으려면 사실상 재작성이다.
3. 컬럼 하나로는 "나갔다 → 복귀 → 또 나감"을 담을 수 없다. 제대로 하려면 `membership_periods` 이력 테이블이 필요하다.
4. `active` 를 보는 모든 화면과 RLS 헬퍼가 "언제 기준인지" 따져야 한다.

**미뤄도 되는 이유**

`small_group_members` 에 `trg_audit` 이 INSERT/UPDATE/DELETE 전부 걸려 있어 이력 원재료가
`audit_logs` 에 계속 쌓인다(감사 시작 2026-07-24). 이력 테이블은 나중에 audit_logs 위에서 재구성할 수 있다.

> 주의: `audit_row()` 는 fail-open(`exception when others then return null`)이라 로깅이 조용히
> 실패할 수 있다. 유일한 출처로 삼기엔 약하다.

**넘어갈 시점**

제외/복귀가 월 단위로 잦아지거나, "작년 이맘때 이 그룹이 몇 명이었나"를 실제로 물어야 할 때.
