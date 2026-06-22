# 소그룹 출석부 (Attendance)

부평동부교회 공동체 소그룹의 출석을 리더가 기록하고, 출석률을 통계로 보는 기능.
웹 우선 구현. SvelteKit + Supabase(anon key + RLS), 게시판과 동일하게 `supabaseBrowser` 클라이언트로 동작.

> DB 마이그레이션은 Supabase 프로젝트 **DBA**(`nfivyduwknskpfhuyzeg`)에 직접 적용되어 있습니다.
> 이 문서가 적용된 스키마/권한의 단일 기록입니다. (로컬 supabase CLI 미사용)

## 구조

- **공동체(communities)** 3개: 열매(≤55세) · 줄기(56–70세) · 뿌리(70세+)
- 각 공동체 아래 **소그룹(small_groups)** 28개
- 소그룹마다 **명단(small_group_members)** — 첫 인원(role=`leader`)이 리더
- **주차(attendance_sessions)** — 주일(셋째주 제외), 2026년 38개 날짜 시드
- 출석은 `attendance_records`에 present 행으로 저장(결석=행 없음)
- **특이사항(member_notes)** — 소그룹원×주차당 1개 (인원별 메모)
- **기타 의견(group_session_notes)** — 소그룹×주차당 1개 (그룹 단위 의견)
- **지정 교역자(attendance_managers)** — 메모/전체 열람 권한자

## 권한 모델 (RLS)

식별: `custom_users.auth_id = auth.uid()` → `app_current_user_id()`

| 데이터 | 소그룹 리더(본인 그룹) | 지정 교역자 | 관리자(level≥100) | 그 외 |
|---|---|---|---|---|
| 소그룹/명단 조회 | ✅ 본인 그룹 | ✅ 전체 | ✅ 전체 | ❌ |
| 명단 편집 | ❌ | ✅ | ✅ | ❌ |
| 출석 기록 조회/입력 | ✅ 본인 그룹 | ✅ 전체 | ✅ 전체 | ❌ |
| 특이사항 / 기타 의견 | ✅ 본인 그룹 | ✅ 전체 | ✅ 전체 | ❌ |
| 교역자 지정 | ❌ | ❌ | ✅(admin) | ❌ |

RLS 헬퍼(모두 SECURITY DEFINER): `app_current_user_id()`, `app_is_admin()`,
`app_is_attendance_manager()`, `app_can_manage()`(admin 또는 교역자), `app_is_group_leader(gid)`.

## 화면 (`/attendance`)

- **출석 체크** (`/attendance`) — 리더용. 그룹/주차 선택 → 출석 체크 + 인원별 특이사항 + 기타 의견 입력.
  하단에 특이사항/기타 의견 모아보기(최근 주차 위), 주차별·인원별 출석 그래프(SVG).
- **통계 대시보드** (`/attendance/dashboard`) — 교역자/관리자용. 전체·공동체·소그룹 출석률.
  "전체출석"은 그룹이 실제 기록한 주차 기준, "최근주차"는 그룹별 마지막 기록 주차.
- **명단 관리** (`/attendance/manage`) — 교역자/관리자용. 구성원 추가/제외·리더지정·프로필교체,
  교역자(목사) 지정(추가/해제는 관리자만).

Header의 "출석부" 메뉴는 리더/교역자/관리자에게만 노출.
날짜 기준은 Asia/Seoul(`todayISO`). 목록 조회는 1000행 제한 대비 `fetchAll`로 페이지네이션.

## 데이터 임포트 (2026 공동체출석부.xlsx)

- 명단 505명(고유 501) → 자동매칭 436 / 동명이인 20 / 신규 49.
- 동명이인은 공동체=연령, 같은 공동체 내 남/여 그룹은 성별로 판별. 같은 공동체·성별이라 못 가린
  3명(김현숙·이명애·최순자)은 임의배정(관리화면에서 정정 가능).
- 신규 49명은 placeholder 프로필 생성(office '성도', member/active true).
- 출석 이력 2977건 입력(엑셀 1 표기 = 출석). 개인 출석수 엑셀과 일치 검증 완료.
- 매칭 검토표: `~/Downloads/출석부_매칭검토.md` (저장소 미포함).

### 선행 사용자 정리 (2026-06-22)
동명이인/더미 정리로 `custom_users` 603 → 549.
백업: `custom_users_backup_20260622` (RLS enabled, service role 전용).
앱 전반의 사용자 식별 FK는 `custom_users.id`가 아니라 **`auth_id`** (posts/likes/comments/messages/user_tokens 등).

## 스키마 DDL (적용본)

```sql
create table communities (
  id bigint generated always as identity primary key,
  name text not null unique, sort_order int not null default 0,
  created_at timestamptz not null default now());

create table small_groups (
  id bigint generated always as identity primary key,
  community_id bigint not null references communities(id) on delete restrict,
  name text not null, sort_order int not null default 0,
  active boolean not null default true, created_at timestamptz not null default now(),
  unique (community_id, name));

create table small_group_members (
  id bigint generated always as identity primary key,
  small_group_id bigint not null references small_groups(id) on delete cascade,
  user_id uuid not null references custom_users(id) on delete cascade,
  role text not null default 'member' check (role in ('leader','member')),
  sort_order int not null default 0, active boolean not null default true,
  joined_at timestamptz not null default now(), created_at timestamptz not null default now(),
  unique (small_group_id, user_id));

create table attendance_sessions (
  id bigint generated always as identity primary key,
  session_date date not null unique, label text,
  sort_order int not null default 0, active boolean not null default true,
  created_at timestamptz not null default now());

create table attendance_records (
  id bigint generated always as identity primary key,
  session_id bigint not null references attendance_sessions(id) on delete cascade,
  small_group_id bigint not null references small_groups(id) on delete cascade,
  member_id bigint not null references small_group_members(id) on delete cascade,
  present boolean not null default true, recorded_by uuid references custom_users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (session_id, member_id));

create table member_notes (
  id bigint generated always as identity primary key,
  session_id bigint references attendance_sessions(id) on delete cascade,
  small_group_id bigint not null references small_groups(id) on delete cascade,
  member_id bigint not null references small_group_members(id) on delete cascade,
  note text not null default '', created_by uuid references custom_users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (member_id, session_id));

create table group_session_notes (
  id bigint generated always as identity primary key,
  small_group_id bigint not null references small_groups(id) on delete cascade,
  session_id bigint not null references attendance_sessions(id) on delete cascade,
  note text not null default '', created_by uuid references custom_users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (small_group_id, session_id));

create table attendance_managers (
  user_id uuid primary key references custom_users(id) on delete cascade,
  note text, created_at timestamptz not null default now());
```

모든 테이블 RLS 활성화. 정책 요지:
- communities/attendance_sessions: 인증 사용자 SELECT, 수정은 `app_can_manage()`.
- small_groups/small_group_members: SELECT = `app_is_group_leader(...) or app_can_manage()`, 수정 = `app_can_manage()`.
- attendance_records: 전 권한 = `app_is_group_leader(small_group_id) or app_can_manage()`.
- member_notes / group_session_notes: 전 권한 = `app_is_group_leader(small_group_id) or app_is_attendance_manager() or app_is_admin()`.
- attendance_managers: SELECT = `app_can_manage()`, 수정 = `app_is_admin()`.
