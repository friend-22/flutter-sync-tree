# flutter-sync-tree
Composite 패턴과 Riverpod을 활용한 계층형 스트림 데이터 동기화 엔진

🌲 flutter-sync-tree
Hierarchical Reactive Data Synchronization Engine for Flutter

flutter-sync-tree는 Composite Pattern과 Riverpod을 결합하여 복잡한 로컬-클라우드 데이터 동기화 로직을 계층적으로 관리하는 강력한 동기화 엔진입니다.

단일 테이블 동기화부터 수십 개의 테이블이 얽힌 복합 동기화까지, 하나의 트리 구조로 관리하고 상태를 실시간으로 추적하세요.

✨ Key Features
Composite Architecture: SyncNode 추상화를 통해 단일 작업(Leaf)과 복합 작업(Composite)을 동일한 인터페이스로 처리합니다.

Reactive State Management: Riverpod과 Stream을 결합하여 동기화 진행률(Progress), 상태(State), 에러(Error)를 실시간 반영합니다.

Smart Throttling: 고빈도 데이터 업데이트 상황에서도 UI 스레드 부하를 최소화하기 위해 지능형 스로틀링을 지원합니다.

Fault Tolerance: 지수 백오프(Exponential Backoff) 기반의 재시도 전략(RetryConfig)과 타임아웃 처리가 내장되어 있습니다.

Pause & Resume: 비동기 스트림 제어를 통해 동기화 작업을 일시 중지하거나 재개할 수 있습니다.

🏗 Architecture
본 프로젝트는 **복합체 패턴(Composite Pattern)**을 기반으로 설계되었습니다.

SyncNode: 모든 동기화 객체의 최상위 추상 클래스.

SyncLeaf: 실제 데이터 소스(Firestore, Drift 등)와 통신하는 최소 단위 작업.

SyncComposite: 여러 개의 SyncNode를 그룹화하여 전체 진행률을 계산하고 상태를 통합 관리.

🚀 Getting Started
1. Define your SyncLeaf
Dart
class MyDataSync extends SyncLeaf {
  MyDataSync({required super.stream, super.key});

  @override
  Future<void> handleSnapshot(QuerySnapshots snapshot, OnSyncOper onSyncOper) async {
    // 동기화 로직 구현 (추가, 수정, 삭제 등)
    onSyncOper(SyncSummary.add);
  }
}
2. Build SyncTree
Dart
final composite = SyncComposite(
  key: 'MainSyncTree',
  primarySyncs: [cloudSync, userSync],
  lateSyncs: [analyticsSync],
);

composite.start();
📊 State Flow
동기화 상태는 다음과 같은 수명 주기를 따릅니다:

SyncInitial: 초기화 상태.

SyncInProgress: 데이터 수신 및 처리 중 (Throttled Progress).

SyncSuccess: 모든 노드의 동기화가 에러 없이 완료됨.

SyncFailure: 노드 중 하나에서 치명적 에러 발생 및 재시도 실패.

🛠 Tech Stack
Language: Dart (Sound Null Safety)

Framework: Flutter

State Management: Riverpod

Patterns: Composite, Mixin, State, Observer

Database Integration: Support for Firestore, Drift (SQLite)

📜 License
This project is licensed under the MIT License - see the LICENSE file for details.

👨‍💻 Author
Your Name - GitLab Profile

Contact - your-email@example.com
