# 교회 일정 캘린더 (Events)

`/events` — 교회 행사 일정을 월 달력으로 보고, 매니저/관리자가 추가·수정·삭제하는 기능.
기존 `church_events` 테이블 활용(스키마 변경 없음). SvelteKit + Supabase(anon key + RLS), supabaseBrowser 구동.

## 화면
- 상단 메뉴 **"교회 일정"**(공개, 비로그인도 열람).
- 월 달력 그리드 + 선택일 상세. 이전/다음 달·오늘 이동, 오늘 강조, 일(빨강)/토(파랑).
- 반복 일정 자동 전개. 다중일 일정은 기간 전체 날짜에 표시.
- **매니저/관리자(level≥50)** 에게만 "일정 추가/수정/삭제" UI 노출(`canEdit`). 미만/비로그인은 보기 전용.

## 권한 (church_events RLS)
- SELECT: 전체 공개. INSERT/UPDATE/DELETE: `roles.level >= 50`.
- 검증(실제 RLS 시뮬레이션): 비로그인·일반(10) = 추가/수정/삭제 차단, 매니저(50)·관리자(100) = 허용. UI 게이트(level≥50)와 일치.

## 구현 메모
- `src/lib/events.ts`: KST(Asia/Seoul) 날짜 유틸 + 반복 전개(`expandEvent`), 월 그리드 범위, 요일 계산.
- 시간은 timestamptz → **KST 기준**으로 표시/배치/전개.
- `recurrence_type`: none/weekly/monthly/yearly. `recurrence_end_date`로 만료.
- **day_of_week 규칙: 1=일 … 7=토** (예: 수=4). 저장 시 모바일앱 호환 위해 day_of_week/day_of_month/month_of_year도 채움.
- 컬럼명 주의: `update_at`(updated_at 아님).
- 조회는 보이는 달 그리드 범위로 한정(반복 일정은 전체 조회 후 전개).

## 데이터
- 2026 연중 행사 계획(요람 PDF 14–15p) **36건**을 `church_events`에 일괄 입력(모두 all-day, recurrence none).
  다중일 5건(제1~4차 20일 은혜路 기도회, 몽골 단기선교 6/27~7/4)은 기간으로 입력.
- **보류(날짜 미정)**: 수요 성경 아카데미(WBA) 개강(1월), 공동체별 수련회(8월).
- 기존 2025년 일정 3건은 그대로 유지(총 39건).
