## flutter-sync-tree
Composite 패턴과 Riverpod을 활용한 계층형 스트림 데이터 동기화 엔진

## 🌲 flutter-sync-tree

Composite 패턴과 Riverpod을 활용한 반응형 데이터 동기화 엔진

flutter-sync-tree는 복잡한 데이터 동기화 로직을 계층적으로 관리하기 위한 Flutter 라이브러리입니다.

단순히 데이터를 옮기는 것을 넘어, 전체 동기화 과정의 상태 관리, 재시도 전략, 스로틀링을 한꺼번에 해결합니다.


## ✨ 주요 기능 (Key Features)

계층형 동기화 구조 (Composite Pattern): 여러 개의 동기화 작업을 하나의 '트리'로 묶어 관리합니다.

반응형 상태 전파 (Riverpod): 동기화 진행률과 에러 상태를 UI에 실시간으로 반영합니다.

지능형 스로틀링 (Throttling): 초당 수백 건의 데이터가 들어와도 UI가 버벅이지 않도록 최적화합니다.

안정적인 재시도 (Retry Policy): 네트워크 장애 시 지수 백오프(Exponential Backoff) 알고리즘으로 자동 재시도합니다.

중단 및 재개 (Pause & Resume): 비동기 작업의 흐름을 완벽하게 제어합니다.


## 🏗 설계 원칙 (Architecture)

이 프로젝트는 확장성과 유지보수성에 올인했습니다.

SyncNode: 모든 동기화의 기본 단위입니다.

SyncLeaf: 실제 데이터를 처리하는 '잎' 노드입니다. (예: Firestore -> 로컬 DB)

SyncComposite: 여러 노드를 포함하는 '가지' 노드입니다. 전체 진행률을 계산합니다.


## 🚀 Getting Started
// 동기화 로직 구현 (추가, 수정, 삭제 등)    
1. Define your SyncLeaf

Dart
class MyDataSync extends SyncLeaf {
  MyDataSync({required super.stream, super.key});
  @override
  Future<void> handleSnapshot(QuerySnapshots snapshot, OnSyncOper onSyncOper) async {  
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


## 📊 State Flow

동기화 상태는 다음과 같은 수명 주기를 따릅니다:

SyncInitial: 초기화 상태.

SyncInProgress: 데이터 수신 및 처리 중 (Throttled Progress).

SyncSuccess: 모든 노드의 동기화가 에러 없이 완료됨.

SyncFailure: 노드 중 하나에서 치명적 에러 발생 및 재시도 실패.


## 🛠 Tech Stack

Language: Dart (Sound Null Safety)

Framework: Flutter

State Management: Riverpod

Patterns: Composite, Mixin, State, Observer


## 📜 License

본 프로젝트는 MIT License를 따릅니다. 누구나 자유롭게 수정하고 사용할 수 있습니다.


## 💖 Thanks To

👨‍💻 Author

Your Name - 이정우


Contact - jw.leec.test@gmail.com
    
