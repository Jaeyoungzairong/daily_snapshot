import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore에 "리스트 하나 = 문서 하나"로 저장하기 위한 최소 추상화.
/// 전체 리스트를 실시간으로 구독(watch)하고, 트랜잭션으로 원자적으로 수정(mutate)한다 —
/// 여러 기기에서 거의 동시에 수정해도, 트랜잭션이 최신 문서를 다시 읽은 뒤 변경을 적용하므로
/// 나중 쓰기가 앞선 변경을 통째로 덮어써 유실시키는 일이 없다.
abstract class CloudListStore {
  const CloudListStore();

  Stream<List<Map<String, dynamic>>> watch(String docKey);

  Future<void> mutate(
    String docKey,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> current) transform,
  );
}

class FirestoreListStore implements CloudListStore {
  FirestoreListStore({required this.uid, FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String docKey) =>
      _firestore.collection('users').doc(uid).collection('data').doc(docKey);

  List<Map<String, dynamic>> _itemsOf(Map<String, dynamic>? data) {
    final items = data?['items'] as List?;
    return items?.cast<Map<String, dynamic>>() ?? [];
  }

  @override
  Stream<List<Map<String, dynamic>>> watch(String docKey) {
    return _doc(docKey).snapshots().map((snapshot) => _itemsOf(snapshot.data()));
  }

  @override
  Future<void> mutate(
    String docKey,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> current) transform,
  ) {
    final ref = _doc(docKey);
    return _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final next = transform(_itemsOf(snapshot.data()));
      transaction.set(ref, {'items': next});
    });
  }
}
