import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../models/attendee.dart';
import '../models/feedback.dart';

class FirestoreRefs {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ==========================================
  // EVENTS COLLECTION
  // ==========================================
  static CollectionReference<Event> events() {
    return _db
        .collection('events')
        .withConverter<Event>(
          fromFirestore: (snapshot, _) {
            final data = snapshot.data() ?? {};
            // Inject the document ID into the map so Freezed can map it to 'required String id'
            data['id'] = snapshot.id;
            return Event.fromJson(data);
          },
          toFirestore: (event, _) {
            final json = event.toJson();
            // Remove the ID before saving to avoid duplicating data unnecessarily
            json.remove('id');
            return json;
          },
        );
  }

  // ==========================================
  // ATTENDEES SUBCOLLECTION
  // ==========================================
  static CollectionReference<Attendee> attendees(String eventId) {
    return _db
        .collection('events')
        .doc(eventId)
        .collection('attendees')
        .withConverter<Attendee>(
          fromFirestore: (snapshot, _) {
            final data = snapshot.data() ?? {};
            data['id'] = snapshot.id;
            data['eventId'] = eventId; // Ensure eventId is present
            return Attendee.fromMap(data, snapshot.id);
          },
          toFirestore: (attendee, _) {
            final json = attendee.toMap();
            json.remove('id');
            json.remove('eventId');
            return json;
          },
        );
  }

  // ==========================================
  // FEEDBACK SUBCOLLECTION
  // ==========================================
  static CollectionReference<EventFeedback> feedback(String eventId) {
    return _db
        .collection('events')
        .doc(eventId)
        .collection('feedback')
        .withConverter<EventFeedback>(
          fromFirestore: (snapshot, _) {
            final data = snapshot.data() ?? {};
            data['id'] = snapshot.id;
            data['eventId'] = eventId;
            return EventFeedback.fromJson(data);
          },
          toFirestore: (feedback, _) {
            final json = feedback.toJson();
            json.remove('id');
            json.remove('eventId');
            return json;
          },
        );
  }
}
