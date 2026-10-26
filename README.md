<p align="center">
    <img width="140px" src="https://raw.githubusercontent.com/hanyuec8/violet/dev/violet/assets/images/logo.png" align="center" alt="Violet Lite Logo" />
</p>
<h1 align="center">Violet Lite</h1>
<p align="center">
    <b>초고속 온디바이스 하이브리드 스트리밍 만화 뷰어</b>
</p>
<p align="center">
    <a href="https://github.com/hanyuec8/violet/releases/latest"><img src="https://img.shields.io/github/v/release/hanyuec8/violet?color=purple&label=Release" alt="Latest Release" /></a>
    <img src="https://img.shields.io/badge/Flutter-3.35.4-blue.svg" alt="Flutter" />
    <img src="https://img.shields.io/badge/Dart-3.9.2-teal.svg" alt="Dart" />
    <img src="https://img.shields.io/badge/Architecture-Triple%20Hybrid%20Stream-orange.svg" alt="Architecture" />
    <img src="https://img.shields.io/badge/License-Apache%202.0-green.svg" alt="License" />
</p>

<p align="center">
    <b><a href="https://github.com/hanyuec8/violet/releases/latest">최신 APK 다운로드</a></b>
    •
    <b><a href="https://github.com/hanyuec8/violet/issues">이슈 제보</a></b>
</p>

---

## 📖 프로젝트 소개

**Violet Lite**는 기존 공식 Violet의 수개월 전 정적 로컬 데이터베이스 의존 구조를 완전히 탈피하여, **Hitomi Nozomi 웹 인덱스**와 **E-Hentai 검색 파이프라인**을 실시간으로 결합한 **트리플 하이브리드 스트리밍 뷰어**입니다.

기존 Violet(`xyz.project.violet`)과 별개의 독립 패키지(`xyz.project.violet.lite`)로 분리되어 데이터 충돌 없이 공존 설치가 가능하며, 첫 실행 시 32MB DB 다운로드 강제 없이 **설치 즉시 0초 만에 메인 화면으로 직행**합니다.

---

## 🏆 오리지널 공식 Violet 대비 전체 변경 사항 종합 (Grand Overhaul)

공식 Violet 대비 현재까지 진행된 핵심 아키텍처 개편 및 기능 개선 종합 내역입니다:

```
[ 기존 공식 Violet ]                 [ Violet Lite (현재) ]
  정적 로컬 DB (수개월 전)     ───►    Hitomi Nozomi 웹 인덱스 + E-Hentai 실시간 하이브리드 스트림
  첫 실행 32MB DB 다운로드 필수  ───►    설치 즉시 0초 메인 화면 직행 (다운로드 화면 완전 제거)
  작품 언어 강제 묶기         ───►    각 언어본 독립 카드 온전 노출 (WorkGrouper 완전 제거)
  대량 북마크 수십 초 로딩     ───►    SQLite 디스크 캐시(ArticleCache) 0.02초 일괄 복원
  탐색 위치 분실               ───►    마지막 본 작품 위치 실시간 영구 보존 & 스마트 점프
  검색 자동완성 타이핑 렉       ───►    200ms 디바운스 & Full Table Scan 배제 초고속 반응
  랜덤 최신작 50개 국부 셔플    ───►    전 기간(0%~100%) 5개 구간 균등 분산 무작위 추천
  레거시 10종 서브프로젝트     ───►    TypeScript/Python 100% 제거, Dart + C# 순수 경량화
```

---

### 1. 데이터 파이프라인 & 스트리밍 혁신
* **첫 실행 시 데이터베이스 다운로드 화면 완전 제거**:
  * 기존에는 첫 실행 시 32MB에 달하는 거대 데이터베이스 다운로드를 필수로 거쳐야 했습니다.
  * Violet Lite는 백그라운드 0.005초 스키마 초기화로 **설치 즉시 0초 만에 메인 화면(`/AfterLoading`)으로 진입**합니다.
* **트리플 하이브리드 실시간 스트리밍 로더 (`HybridLoader`)**:
  * Hitomi Nozomi Range 인덱스 + E-Hentai 웹 검색 + 로컬 SQLite DB(공통작 승격) 3중 병렬 스트림 결합.
  * 방금 사이트에 업로드된 전 세계 최신 신작까지 딜레이 없이 실시간으로 탐색할 수 있습니다.
* **5중 대조 검증 파이프라인 (`verifyAndTagPupilArticles`)**:
  * 로컬 DB ID, 다중 서브타이틀 토큰 매칭(`isTitleMatched`), 북마크 DB, E-Hentai 검색, EHash 존재 여부 등 5중 교차 검증으로 독점작(`pupil_only`)과 공통작(`common`)을 엄격히 분류.
* **언어 묶기(`WorkGrouper`) 완전 제거 & 개별 독립 작품 노출**:
  * 각 언어본 작품들을 하나로 묶어 숨기던 로직을 완전히 제거하여, 한국어본, 일본어본, 영어본 등이 독립 카드로 온전하게 검색/노출됩니다.
* **인메모리 세션 캐시(Session Cache)**:
  * 품번 $\to$ 뱃지 소스(`common` / `pupil` / `violet`) 및 파싱된 메타데이터를 RAM에 유지하여 중복 네트워크 요청 0건 달성.

---

### 2. 검색 & 카탈로그 & 자동완성 혁신
* **랜덤 태그(`random`) 전 기간 균등 분산 무작위 샘플링 복원**:
  * 최신 50개(1페이지) 범위 내에서만 섞이던 문제를 해결하고, 전체 작품 수($N$)의 전 기간(0% \~ 100%)을 5개 구간(과거, 중기, 중후기, 최근, 최신)으로 균등 분할하여 **10년 전 고전 명작부터 최신작까지 골고루 융합된 진짜 무작위 추천**을 제공합니다.
* **검색창 자동완성 초고속 최적화**:
  * **200ms 타이핑 디바운스(`Timer`)** 및 비동기 레이스 컨디션 방지 가드를 적용.
  * dummy DB 환경에서 불필요한 Full Table Scan LIKE 쿼리를 0ms로 조기 스킵하여 타이핑 렉을 원천 박멸했습니다.
* **온디맨드 로컬 태그 카탈로그 (`HitomiTagCatalog`)**:
  * Hitomi 공식 A\~Z 전체 작가/그룹 목록을 온디맨드로 로컬 캐싱하여 이후 0ms(추가 네트워크 0B) 즉시 검색 지원 (국내 ISP 차단 우회 Direct IP 탑재).
* **스마트 랭킹 우선순위**:
  * 접두사 일치(Prefix Match) 우선 가산점, 0작품 단문자 감점 등으로 원하는 대중 태그(`scat`, `anal` 등)나 작가가 검색창 최상단에 즉시 노출.
* **날짜(`date`) 및 번호(`id`) 구간/비교 검색 전면 지원**:
  * `date:2024`, `date:2022~2024`, `date>=2024`, `date<=2021`, `id:1000000~2000000`, `id>=3000000` 등 정밀 필터링 지원.
* **언어별 검색 인덱스 직결**:
  * `lang:`, `language:` 쿼리 시 해당 언어 전용 Nozomi 인덱스(`index-$lang.nozomi`) 직결 및 표준 지원 언어 전체 자동완성.

---

### 3. 탐색 위치 기억 & 스마트 점프 (이어보기 UX)
* **마지막 본 작품 위치 및 품번 실시간 영구 보존**:
  * 검색 화면을 스크롤하다 앱을 닫거나 다른 화면으로 이동해도, **내가 마지막으로 보던 작품 위치(품번 및 오프셋)를 영구 보존**합니다.
* **신작 유입 오차 자동 보정 스마트 점프**:
  * 새로운 신작이 수십\~수백 개 유입되어 오프셋 번호가 밀려도, 고유 품번을 추적하여 정확히 그 작품 위치로 스크롤을 복원합니다.
* **임의 번호 즉시 점프 (Item Jump)**:
  * maxPage 제한을 철폐하여 1353, 5000 등 원하는 임의의 작품 번호로 즉시 점프 지원.
* **`[📍 마지막 본 위치]` 시각 마커 오버레이**:
  * 모든 뷰 모드(그리드/디테일/울트라)에서 썸네일 좌측 하단에 마지막 열람 위치 뱃지 표시.
* **태그 즐겨찾기 상단 팝업 다이얼로그 개편**:
  * 화면 하단 FAB 겹침을 해결하고 한 손 조작성을 극대화한 검색창 직하단 상단 팝업 다이얼로그 제공.

---

### 4. 북마크 & 열람 기록 & 캐싱 신뢰성 혁신
* **대량 북마크 초고속 복원 (`ArticleCache`)**:
  * SQLite 디스크 영구 캐시 탑재로 900개 등 대량 북마크 진입 시 단 1회의 쿼리로 **0.02초 만에 일괄 복원**.
* **인터랙티브 진행률 UX (`_TagFetchProgressDialog`)**:
  * 북마크 폴더 태그 분류 시 1개씩 실시간으로 차오르는 부드러운 로딩바, 실시간 진행률(N/Total 및 %), [지금 열기] 및 [취소] 버튼 제공.
* **미분류 북마크 읽음 진행도(빨간 바) 영구 보존**:
  * 기본 '미분류' 북마크 폴더에 보관된 작품은 7일/30일 제한 없이 읽기 진행도 바 및 뷰어 이어보기 상태가 영구 보존됩니다.
* **열람 기록(`RecordViewPage`) 완전 복구**:
  * 무한 로딩/회색 에러 박스를 원천 박멸하고, 로컬 DB + 디스크 캐시 + 병렬 웹 수집 3단계 고속 파이프라인 탑재.
* **북마크 DB 가져오기/내보내기 결함 완벽 수정**:
  * Android SAF MimeTypeMap 미등록으로 인한 파일명 손상(`.db (13)`) 자동 복원 및 첫 16바이트 SQLite 헤더 검증.

---

### 5. 작가 화면 (`ArtistInfoPage`) 완전 개편
* **언어 인덱스 직결 및 타 언어 제목 매칭에 의한 누락 방지**:
  * 타 언어 제목 유사성으로 인한 삭제 버그를 제거하고, 선택 언어 인덱스(`kuromotokun-korean.nozomi` 등)로 48개 등 전체 작품 100% 수집.
* **한국어 부재 시 안내 Empty State UI**:
  * 한국어 작품이 없는 작가 진입 시 강제로 전체 목록으로 튀거나 더보기 버튼이 노출되는 결함을 차단하고, 안내 화면 표시.
* **Range 0-0 기반 작가 총 작품 수 초경량 캐싱**:
  * `(0)` 대신 실제 총 작품 수(예: `(9)`)를 헤더로부터 0.05초 만에 추출하여 실시간 반영.

---

### 6. 뷰어 & UI 렌더링 안정성 (크래시 박멸)
* **`_dependents.isEmpty` 어설션 크래시 원천 박멸**:
  * 바텀시트 해제 시 플러터 엘리먼트 트리를 오염시키던 위젯 인스턴스 캐싱 안티패턴 제거.
* **GlobalKey 충돌 및 뷰어 먹통 해결**:
  * `imgKeys`를 `ValueKey`로 안정화하여 `Duplicate GlobalKey detected` 충돌 방지.
* **동적 이미지 높이 즉시 계산**:
  * 50ms 딜레이 기반 `findRenderObject` 측정을 제거하고, `ExtendedImageState` 종횡비(`aspectRatio`) 기반 즉시 높이 계산 및 부드러운 스크롤 보정 적용.
* **무한 스크롤 하단 덧붙임 깜빡임(Flicker) 원천 박멸**:
  * 추가 페이지 로딩 시 기존 0\~N-1 카드들의 위젯 State 및 썸네일 컨트롤러 파괴를 방지하여 부드러운 하단 덧붙임 구현.

---

### 7. 아키텍처 대규모 경량화
* **불필요한 레거시 서브프로젝트 10종 완전 삭제**:
  * `violet-server`, `violet-web`, `violet-batch`, `tag-info`, `violet-llm-search`, `violet-backend-core`, `violet-server-hook`, `violet-search`, `violet-message-search-core`, `violet-message-search-client` 및 `.gitmodules` 완전 삭제.
* **프로젝트 언어 대폭 단순화**:
  * TypeScript, Python, JavaScript를 100% 완전 제거하여 메인 스택을 **Dart (Flutter) + C# (hsync)** 2개 언어로 압축.

---

### 8. 패키지 분리 및 무설치급 초고속 실행
* **Violet Lite 독립 패키지 (`xyz.project.violet.lite`)**:
  * 기기에 원래 설치되어 있던 오리지널 공식 Violet(`xyz.project.violet`)과 데이터 충돌 없이 별개 앱으로 안전하게 공존 설치됩니다.

---

## 🔍 고급 검색 문법 완벽 가이드

| 문법 패턴 | 검색어 예시 | 상세 설명 |
| :--- | :--- | :--- |
| **전 기간 랜덤** | `random` | 10년 전 고전 명작부터 최신작까지 전 기간 골고루 융합된 무작위 추천 |
| **연도 범위** | `date:2024` | 2024년 1년 전체에 발행된 작품 |
| | `date:2022~2024` | 2022년부터 2024년까지의 모든 작품 |
| **상세 날짜** | `date:2023-01-01~2023-06-30` | 2023년 상반기 작품만 정밀 검색 |
| **날짜 비교** | `date>=2024` | 2024년 1월 1일 이후 발행된 최신작 |
| | `date<=2021` | 2021년 12월 31일 이전 과거작 |
| **품번 구간** | `id:2000000~3000000` | 200만번대 작품 번호 구간 검색 |
| | `id>=3500000` | 350만번 이상 초신작 검색 |
| **복합 검색** | `lang:korean date>=2024` | 2024년 이후 한국어 번역 작품 |
| | `female:big_breasts date:2022~2024` | 2022\~2024년 기간의 거유 태그 작품 |
| | `artist:michoking date<=2020` | 해당 작가의 2020년 이전 작품 |

---

## 📱 빌드 및 설치

### 요구 사항
* Flutter SDK 3.35.4 이상
* Android NDK 27.0.12077973
* Rust 툴체인 (Cargokit)
* JDK 21

### 빌드 및 배포
```bash
# 1. 의존성 설치
cd violet
flutter pub get

# 2. 디버그 APK 빌드
flutter build apk --debug

# 3. 실기기 설치
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## 📄 라이선스

This project is licensed under the Apache-2.0 License.
Copyright (C) 2020-2026 violet-team & Contributors.
