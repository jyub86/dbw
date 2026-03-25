# 부평동부교회 웹페이지

부평동부교회 공식 웹사이트입니다.

## 기술 스택

- [SvelteKit](https://kit.svelte.dev/) - 웹 프레임워크
- [Svelte 5](https://svelte.dev/) - UI 프레임워크
- [Tailwind CSS 4](https://tailwindcss.com/) - 스타일링
- [TypeScript](https://www.typescriptlang.org/) - 타입 시스템
- [Supabase](https://supabase.com/) - 백엔드 데이터베이스
- [Vite](https://vitejs.dev/) - 빌드 도구

## 페이지 구성

| 경로 | 설명 |
|------|------|
| `/` | 메인 홈 |
| `/about` | 교회 소개 |
| `/news` | 교회 소식 |
| `/board` | 게시판 |
| `/sermons` | 설교 영상 |

## 개발 환경 설정

의존성 패키지를 설치합니다.

```sh
bun install
```

개발 서버를 실행합니다.

```sh
bun run dev
```

## 빌드

프로덕션 빌드를 생성합니다.

```sh
bun run build
```

빌드 결과물을 로컬에서 미리 볼 수 있습니다.

```sh
bun run preview
```
