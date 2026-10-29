#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
extract_expunged.py
원본 데이터베이스와 Hitomi 실시간 Nozomi 인덱스를 비교하여,
삭제(Expunged/DMCA)된 작품들만 정확히 추출해 독립된 초경량 DB(SQLite & Gzip)를 생성하는 도구입니다.
"""

import argparse
import gzip
import os
import sqlite3
import struct
import sys
import time
import urllib.request
from collections import Counter

# 콘솔 UTF-8 출력 보장
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass


def fetch_active_ids(lang: str = 'korean', custom_url: str = None) -> set[int]:
    """Hitomi 공식 CDN으로부터 현재 활성 작품 번호 목록을 다운로드하여 set으로 반환합니다."""
    if custom_url:
        url = custom_url
    elif lang == 'all':
        url = 'https://ltn.gold-usergeneratedcontent.net/index-all.nozomi'
    else:
        url = f'https://ltn.gold-usergeneratedcontent.net/index-{lang}.nozomi'

    print(f'[*] Hitomi 실시간 색인 다운로드 중... ({url})')
    req = urllib.request.Request(
        url,
        headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://hitomi.la/',
        },
    )

    start_t = time.time()
    with urllib.request.urlopen(req, timeout=30) as res:
        data = res.read()
    elapsed = time.time() - start_t

    total_count = len(data) // 4
    print(
        f'[+] 다운로드 완료: {len(data) / 1024 / 1024:.2f} MB ({total_count:,}개 활성 작품, {elapsed:.2f}초)'
    )

    active_ids = set()
    for i in range(total_count):
        gid = struct.unpack('>I', data[i * 4 : (i + 1) * 4])[0]
        active_ids.add(gid)

    return active_ids


def build_expunged_database(
    source_db_path: str,
    output_db_path: str,
    lang: str = 'korean',
    active_ids: set[int] = None,
) -> tuple[int, int, list[tuple[str, int]]]:
    """원본 DB와 활성 ID 목록을 대조하여 삭제된 작품만 추출하고 새 SQLite DB를 구축합니다."""
    print(f'[*] 원본 데이터베이스 연결 중: {source_db_path}')
    if not os.path.exists(source_db_path):
        raise FileNotFoundError(f'원본 DB를 찾을 수 없습니다: {source_db_path}')

    src_conn = sqlite3.connect(source_db_path)
    src_cur = src_conn.cursor()

    # 원본 테이블 스키마 조회
    src_cur.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='HitomiColumnModel'"
    )
    schema_row = src_cur.fetchone()
    if not schema_row:
        raise ValueError(
            'HitomiColumnModel 테이블이 원본 데이터베이스에 존재하지 않습니다.'
        )
    schema_sql = schema_row[0]

    # 대상 쿼리
    if lang == 'all':
        query = 'SELECT * FROM HitomiColumnModel'
        params = ()
    else:
        query = 'SELECT * FROM HitomiColumnModel WHERE Language = ?'
        params = (lang,)

    src_cur.execute(query, params)
    cols = [desc[0] for desc in src_cur.description]
    id_idx = cols.index('Id')
    artists_idx = cols.index('Artists')
    title_idx = cols.index('Title')

    all_rows = src_cur.fetchall()
    total_source_count = len(all_rows)
    print(
        f'[+] 원본 DB 분석 대상: 총 {total_source_count:,}건 (선택 언어: {lang})'
    )

    # 차집합(Diff) 추출: active_ids에 없는 품번 선별
    deleted_rows = [r for r in all_rows if r[id_idx] not in active_ids]
    deleted_count = len(deleted_rows)
    print(f'[+] 추출된 삭제(Expunged) 작품: 총 {deleted_count:,}건')

    # 새로운 SQLite 데이터베이스 파일 생성
    if os.path.exists(output_db_path):
        os.remove(output_db_path)

    os.makedirs(os.path.dirname(os.path.abspath(output_db_path)), exist_ok=True)
    dst_conn = sqlite3.connect(output_db_path)
    dst_cur = dst_conn.cursor()

    # 테이블 생성 및 레코드 삽입
    dst_cur.execute(schema_sql)
    placeholders = ','.join(['?'] * len(cols))
    dst_cur.executemany(
        f'INSERT INTO HitomiColumnModel VALUES ({placeholders})', deleted_rows
    )

    # 검색 성능을 위한 고속 인덱스 생성
    print('[*] 검색 가속 인덱스 생성 중 (Id, Artists, Title)...')
    dst_cur.execute(
        'CREATE INDEX IF NOT EXISTS idx_expunged_id ON HitomiColumnModel(Id)'
    )
    dst_cur.execute(
        'CREATE INDEX IF NOT EXISTS idx_expunged_artists ON HitomiColumnModel(Artists)'
    )
    dst_cur.execute(
        'CREATE INDEX IF NOT EXISTS idx_expunged_title ON HitomiColumnModel(Title)'
    )

    dst_conn.commit()

    # SQLite VACUUM으로 파일 압축 및 최적화
    print('[*] SQLite VACUUM 최적화 수행 중...')
    dst_cur.execute('VACUUM')
    dst_conn.close()
    src_conn.close()

    # Gzip 압축 파일 생성
    gz_path = output_db_path + '.gz'
    with open(output_db_path, 'rb') as f_in:
        with gzip.open(gz_path, 'wb', compresslevel=9) as f_out:
            f_out.writelines(f_in)

    # 통계: 작가별 피해 집계
    artist_counter = Counter()
    for row in deleted_rows:
        raw_artist = row[artists_idx]
        if raw_artist:
            # |artist1|artist2| 형태 분리
            names = [a.strip() for a in raw_artist.split('|') if a.strip()]
            for name in names:
                if name.lower() not in ('n/a', 'none', ''):
                    artist_counter[name] += 1

    top_artists = artist_counter.most_common(10)
    return total_source_count, deleted_count, top_artists


def main():
    parser = argparse.ArgumentParser(
        description='Hitomi 원본 DB 대비 삭제작 전용 초경량 DB 생성기'
    )
    parser.add_argument(
        '--source',
        default='violet/test/db/data.db',
        help='원본 data.db 경로 (기본값: violet/test/db/data.db)',
    )
    parser.add_argument(
        '--output',
        default='expunged.db',
        help='출력할 SQLite DB 경로 (기본값: expunged.db)',
    )
    parser.add_argument(
        '--lang',
        default='korean',
        choices=['korean', 'all', 'japanese', 'english'],
        help='대조할 언어 (기본값: korean)',
    )
    parser.add_argument(
        '--nozomi-url',
        default=None,
        help='사용자 지정 Nozomi 인덱스 URL',
    )

    args = parser.parse_args()

    print('=' * 65)
    print('  Hitomi Expunged Database Extractor')
    print('=' * 65)

    # 1단계: 실시간 활성 목록 수신
    active_ids = fetch_active_ids(lang=args.lang, custom_url=args.nozomi_url)

    # 2단계: 삭제작 추출 및 새 DB 구축
    total_src, deleted_cnt, top_artists = build_expunged_database(
        source_db_path=args.source,
        output_db_path=args.output,
        lang=args.lang,
        active_ids=active_ids,
    )

    raw_size = os.path.getsize(args.output)
    gz_size = os.path.getsize(args.output + '.gz')

    print('=' * 65)
    print('  추출 결과 요약')
    print('=' * 65)
    print(f'- 원본 DB 총 작품 수: {total_src:,}건')
    print(f'- 현재 Hitomi 생존 작품 수: {len(active_ids):,}건')
    print(f'- 추출된 순수 삭제작: {deleted_cnt:,}건 ({deleted_cnt / total_src * 100:.2f}%)')
    print(f'- 생성된 DB 파일 (SQLite): {args.output} ({raw_size / 1024 / 1024:.2f} MB)')
    print(f'- 압축 배포용 파일 (Gzip): {args.output}.gz ({gz_size / 1024 / 1024:.2f} MB)')
    print('-' * 65)
    print('  가장 많은 작품이 삭제된 상위 작가 Top 10:')
    for rank, (artist, cnt) in enumerate(top_artists, 1):
        print(f'   {rank:2d}. {artist}: {cnt}권 삭제됨')
    print('=' * 65)


if __name__ == '__main__':
    main()
