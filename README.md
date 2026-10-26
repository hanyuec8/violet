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

## 🚀 기존 공식 Violet 대비 주요 변경 사항 및 개선점

### 1. 첫 실행 시 데이터베이스 다운로드 화면 완전 제거
* **기존**: 앱을 처음 설치하면 32MB에 달하는 거대 데이터베이스를 내려받아야 하거나 다운로드 화면을 필수로 거쳐야만 메인 화면으로 진입할 수 있었습니다.
* **개선**: 첫 실행 시 데이터베이스 선택/다운로드 과정을 완전히 건너뛰며, 백그라운드에서 0.005초 만에 기본 스키마를 초기화하여 **앱 실행 즉시 0초 만에 메인 화면(`/AfterLoading`)으로 진입**합니다.

### 2. 트리플 하이브리드 실시간 스트리밍 로더
* **기존**: 로컬 DB에 수록된 과거 작품만 검색/열람할 수 있었습니다.
* **개선**: Hitomi의 Nozomi Range 인덱스와 E-Hentai 웹 검색을 병렬 스트림으로 수집하여, **방금 사이트에 업로드된 전 세계 최신 신작까지 딜레이 없이 실시간으로 탐색**할 수 있습니다. 로컬 DB에 수록된 공식 작품은 100% 공통 뱃지로 자동 승격됩니다.

### 3. 랜덤 태그(`random`) 전 기간 균등 분산 무작위 샘플링 복원
* **기존**: 온라인 검색 시 최신 50개(1페이지) 범위 내에서만 순서가 바뀌어 최근 며칠간 올라온 국부적인 기간의 작품만 반복 노출되던 문제가 있었습니다.
* **개선**: 전체 총 작품 수(수만\~수십만 개)의 전 기간(0% \~ 100%)을 5개 구간(과거, 중기, 중후기, 최근, 최신)으로 균등 분할하고 각 구간에서 무작위 오프셋을 추출하여, **10년 전 고전 명작부터 최신 신작까지 전 기간에 걸쳐 골고루 융합된 진짜 무작위 추천**을 제공합니다.

### 4. 검색창 자동검색어(자동완성) 초고속 최적화
* **기존**: 키보드를 칠 때마다 비동기 쿼리가 밀리고 무거운 SQLite 풀 스캔(Full Table Scan)이 연속으로 실행되어 타이핑 렉이 발생했습니다.
* **개선**: **200ms 타이핑 디바운스(`Timer`)** 및 최신 토큰 가드를 적용하고, dummy DB 환경에서 불필요한 Full Table Scan을 0ms로 조기 스킵하여 **부드럽고 쾌적한 즉각 반응 자동완성**을 구현했습니다.

### 5. 날짜(`date`) 및 번호(`id`) 구간/비교 검색 전면 지원
* **연도 구간 검색**: `date:2024`, `date:2022~2024`
* **상세 날짜 구간**: `date:2023-01-01~2023-06-30`
* **비교 연산자**: `date>=2024`, `date<=2021`, `date>=2023-06-01`
* **번호 구간 필터**: `id:1000000~2000000`, `id>=3000000`
* **복합 검색 조합**: `lang:korean date>=2024`, `female:big_breasts date:2022~2024`

### 6. 마지막 본 위치 기억 & 스마트 점프
* 검색 화면을 스크롤하다 앱을 닫거나 다른 화면으로 이동해도, **내가 마지막으로 보던 작품 위치(품번 및 오프셋)를 영구 보존**합니다.
* 아이템 점프 다이얼로그에서 [이어서 보기] 원클릭 이동을 지원하며, 썸네일 좌측 하단에 `[📍 마지막 본 위치]` 시각 마커를 오버레이로 표시합니다.

### 7. 미분류 북마크 읽음 진행도(빨간 바) 영구 보존
* 기본 '미분류' 북마크 폴더에 보관된 작품은 기간 제한 없이 읽기 진행도 바 및 뷰어 이어보기 상태가 영구 보존됩니다.

### 8. 레거시 코드베이스 10종 대규모 경량화
* 더 이상 사용되지 않는 과거 레거시 서브프로젝트(`violet-server`, `violet-web`, `violet-batch`, `tag-info` 등 10종)와 TypeScript, Python 코드를 100% 완전 정리하여, **Dart (Flutter) + C# (hsync)** 중심의 슬림하고 견고한 모던 아키텍처로 압축했습니다.

---

## 🔍 검색 문법 팁

| 검색어 예시 | 설명 |
| :--- | :--- |
| `random` | 전 기간(10년 전 고전부터 최신작까지) 무작위 추천 |
| `date:2024` | 2024년 1년 전체에 발행된 작품 |
| `date:2022~2024` | 2022년부터 2024년까지의 작품 |
| `date>=2024` | 2024년 1월 1일 이후 최신작 |
| `id:2000000~3000000` | 200만번대 작품 번호 구간 검색 |
| `lang:korean date>=2024` | 2024년 이후 한국어 번역 작품 |
| `artist:michoking` | 해당 작가의 모든 작품 검색 |

---

## 📱 빌드 및 설치

### 요구 사항
* Flutter SDK 3.35.4 이상
* Android NDK 27.0.12077973
* Rust 툴체인 (Cargokit)
* JDK 21

### 빌드 명령어
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
