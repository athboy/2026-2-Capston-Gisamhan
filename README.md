# 🏀 ARC 45 (Basketball Shot Analyzer)

**iOS 18+ 온디바이스 AI 기반 실시간 농구 슈팅 아크 및 입사각(45°) 분석 앱**

**ARC 45**는 카메라로 슈팅 궤적을 실시간 추적하여 공의 입사각(Entry Angle), 성공 여부, 그리고 이상적인 목표 아크(45° ± 2°)의 일관성을 즉각 분석하고 시각화합니다. 모든 영상 처리와 AI 추론은 외부 서버 전송 없이 기기 내부(On-Device)에서 실시간으로 동작합니다.

---

## ✨ 주요 기능

* **실시간 카메라 슈팅 분석 (`LiveCameraView`)**
  * 가로 와이드 전체화면 뷰파인더에서 슈팅 궤적과 최고점(`SHOT ARC`), 입사각(`SHOT ANGLE`)을 실시간 오버레이로 표시합니다.
* **온디바이스 AI 림·공 자동 탐지 (`RimAutoDetector` & `Vision`)**
  * 실내 체육관과 야외 코트 데이터를 통합 학습한 Core ML 객체 탐지 모델(`RimDetector.mlmodel`)을 탑재하여 골대(Rim)와 빠르게 날아가는 농구공(Ball)을 실시간으로 인식합니다.
* **4단계 정밀 보정 및 촬영 셋업 가이드 (`CameraCalibration` & `ShootingGuide`)**
  * 기기 자이로·모션 센서(`MotionService`)를 연동해 좌우(Roll)·위아래(Pitch) 수평 상태를 실시간으로 체크합니다.
  * **림 지정 → 백보드 상단 → 백보드 하단 → 보정 확인 및 고정**의 4단계 보정 워크플로우와 수동 림 크기 조절 슬라이더를 지원합니다.
* **스포츠 HUD 실시간 대시보드 (`HUDTheme`)**
  * 매 슈팅 직후 입사각 수치와 피드백 배너(`PERFECT` / `FLAT` / `STEEP`), 득점 여부(`GOAL` / `MISS`)를 표시합니다.
  * 목표 각도(45° ± 2°) 적중률 링 게이지, 시도 횟수(`SHOTS`), 성공 횟수(`GOAL`), 평균 입사각(`AVG`), 각도 편차(`SPREAD`), 궤적 미니맵(`ArcMapView`), 슈팅별 입사각 추이 차트(`Swift Charts`)를 한눈에 제공합니다.
* **슈팅 기록 및 세부 튜닝 (`HistoryView` & `SettingsView`)**
  * 세션별 누적 슈팅 기록을 모아 확인하고, 현장 환경에 맞춰 인식 및 분석 파라미터를 세부 조정할 수 있습니다.

---

## 📱 사용 순서 (실시간 카메라 분석)

1. **ARC 45** 앱을 실행하고 가로 전용 메인 화면에서 **실시간 카메라 분석**을 탭합니다.
2. 아이폰을 가로 방향으로 삼각대에 고정하고, 슈터 측면(가슴 높이 약 1.2~1.5m)에서 골대와 슈터가 함께 보이도록 배치합니다.
3. 좌측(또는 우측) **SETUP CHECKLIST**를 보며 기기 기울기를 맞추고, 가이드 영역 안에 골대 림을 위치시킵니다.
   * 골대 방향에 따라 **림: 우측 / 림: 좌측** 버튼을 눌러 UI 패널이 골대를 가리지 않도록 전환할 수 있습니다.
4. AI가 림을 자동 인식(`RIM LOCKED`)하거나, **보정 시작** 버튼을 눌러 림과 백보드 상·하단을 지정해 위치를 고정(`CALIBRATED`)합니다.
5. `READY` 상태가 되면 패널이 컴팩트 모드로 자동 전환되며, 슈팅할 때마다 실시간 포물선 궤적과 입사각 분석 리포트가 집계됩니다.
   * 통계 패널을 길게 누르면 현재 세션 기록을 초기화할 수 있습니다.

---

## 🗂 프로젝트 구조 (MVVM 아키텍처)

```text
BasketballShotAnalyzer (ARC 45)
├── App
│   ├── BasketballShotAnalyzerApp.swift   # 앱 진입점
│   └── AppDelegate.swift                 # 가로 전용(Landscape) 화면 방향 제어
├── Models
│   ├── NormalizedGeometry.swift          # 화면 비율 정규화 좌표계 모델
│   ├── RimCalibration.swift              # 림 중심 좌표 및 폭 보정 모델
│   ├── CameraCalibration.swift           # 백보드 상·하단 및 기울기 보정 모델
│   ├── ShootingGuide.swift               # 촬영 준비 체크리스트 및 가이드 영역 계산
│   ├── ShotAnalysis.swift                # 슈팅 입사각, 피드백, 결과 리포트 모델
│   ├── ShotSession.swift                 # 슈팅 세션 데이터 모델
│   ├── ScreenOrientation.swift           # 기기 가로 방향(좌/우) 회전 각도 계산
│   ├── Tuning.swift                      # 탐지 및 분석 세부 파라미터 모델
│   └── VideoTransferable.swift           # 영상 데이터 로드 모델
├── Services
│   ├── LiveCameraService.swift           # AVFoundation 실시간 카메라 세션 관리
│   ├── RimAutoDetector.swift             # Core ML 기반 림 자동 탐지 서비스
│   ├── TrajectoryEstimator.swift         # 농구공 궤적 포인트 추적 및 필터링
│   ├── PoseEstimator.swift               # Vision 기반 슈터 손목·릴리즈 포즈 추정
│   ├── LiveShotAnalyzer.swift            # 실시간 프레임 파이프라인 및 슛 판정
│   ├── ShotAnalysisService.swift         # 녹화 영상 프레임 분석 서비스
│   ├── ShotPhysics.swift                 # 포물선 피팅, 입사각 및 물리 연산
│   ├── MotionService.swift               # Core Motion 기반 기기 롤·피치 기울기 측정
│   ├── VideoAssetInfo.swift              # 비디오 에셋 메타데이터 추출
│   └── VideoFrameReader.swift            # 비디오 프레임 디코딩
├── ViewModels
│   ├── LiveShotViewModel.swift           # 실시간 카메라 분석 상태 및 보정 로직 관리
│   └── ShotAnalysisViewModel.swift       # 앨범 영상 분석 상태 관리
├── Views
│   ├── ContentView.swift                 # ARC 45 가로 전용 와이드 홈 화면
│   ├── LiveCameraView.swift              # 실시간 카메라 뷰파인더 및 사이드 HUD
│   ├── HUDTheme.swift                    # 공통 다크 스포츠 테마, 링 게이지, 미니맵 컴포넌트
│   ├── HistoryView.swift                 # 슈팅 세션 기록 조회 화면
│   ├── SettingsView.swift                # 분석 파라미터 튜닝 설정 화면
│   ├── AnalysisResultCard.swift          # 슈팅 분석 상세 결과 카드 UI
│   └── VideoPreview.swift                # 비디오 플레이어 및 궤적 프리뷰
└── Resources
    ├── Assets.xcassets                   # 앱 아이콘 및 컬러 에셋
    └── RimDetector.mlmodel               # 실내외 림(Rim) 및 공(Ball) 탐지 Core ML 모델

---

## 🛠 기술 스택 및 분석 원리
환경 및 프레임워크: iOS 18.0+, Swift 6, SwiftUI, AVFoundation, Vision, Core ML, Core Motion, Swift Charts

분석 원리: 정식 규격 림 지름(45cm)과 백보드 보정 좌표를 물리적 기준 척도로 삼고, 공의 중심점 이동 궤적을 2차 곡선(포물선)으로 회귀 분석하여 림 평면 진입 시점의 입사각(Entry Angle)과 득점 여부를 산출합니다. 카메라와 림 사이의 원근 왜곡이나 기울기가 발생할 경우 4단계 보정(CameraCalibration)과 자이로 수평 가이드를 통해 오차를 최소화합니다.