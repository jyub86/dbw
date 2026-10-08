/**
 * CSV 생성·다운로드 유틸.
 *
 * xlsx 라이브러리를 쓰지 않는다. 의존성이 늘고 번들이 커지는데,
 * BOM 을 붙인 CSV 면 엑셀에서 더블클릭으로 바로 열리고 한글도 깨지지 않는다.
 */

export type Col<T> = { key: string; label: string; get: (row: T) => unknown };

/** RFC 4180: 쉼표·따옴표·줄바꿈이 있으면 따옴표로 감싸고 내부 따옴표는 두 번 쓴다. */
function cell(v: unknown): string {
	if (v === null || v === undefined) return '';
	const s = String(v);
	return /[",\n\r]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
}

export function toCsv<T>(rows: T[], cols: Col<T>[]): string {
	const head = cols.map((c) => cell(c.label)).join(',');
	const body = rows.map((r) => cols.map((c) => cell(c.get(r))).join(',')).join('\r\n');
	return rows.length ? `${head}\r\n${body}` : head;
}

/**
 * CSV 를 파일로 내려받는다.
 * 앞에 BOM(﻿)을 붙여야 엑셀이 UTF-8 로 인식한다. 없으면 한글이 깨진다.
 */
export function downloadCsv(filename: string, csv: string) {
	const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = filename;
	document.body.appendChild(a);
	a.click();
	a.remove();
	// 즉시 해제하면 일부 브라우저에서 저장이 취소된다.
	setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** 'YYYYMMDD' (파일명용) */
export const stamp = (iso: string) => iso.replaceAll('-', '');
