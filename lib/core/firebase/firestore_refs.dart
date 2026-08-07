import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../models/attendee.dart';
import '../models/feedback.dart';

// Paths are org-scoped: orgs/{orgId}/events/{eventId}/{attendees,feedback}.
// See docs/saas-schema.md for why (and for the one deliberate exception —
// live_feed_providers.dart's cross-event admin feed, which needs a
// denormalised orgId field on attendee docs since a collectionGroup query
// can't be scoped by path alone).
//
// The legacy flat events/{eventId}/... tree that predates this migration
// still exists in Firestore (functions/scripts/migrate-to-orgs.js copies
// FROM it but never deletes it) — nothing here reads it anymore, and
// firestore.rules denies all client access to it by default.
class FirestoreRefs {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _orgEvents(String orgId) {
    return _db.collection('orgs').doc(orgId).collection('events');
  }

  // ==========================================
  // EVENTS COLLECTION (org-scoped)
  // ==========================================
  static CollectionReference<Event> events(String orgId) {
    return _orgEvents(orgId).withConverter<Event>(
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
  // EVENT DOCUMENT for a given id, within an org
  // ==========================================
  static DocumentReference<Event> event(String orgId, String docId) {
    return events(orgId).doc(docId);
  }

  // ==========================================
  // ATTENDEES SUBCOLLECTION (org + event scoped)
  // ==========================================
  static CollectionReference<Attendee> attendees(String orgId, String eventId) {
    return _orgEvents(orgId)
        .doc(eventId)
        .collection('attendees')
        .withConverter<Attendee>(
          fromFirestore: (snapshot, _) {
            final data = snapshot.data() ?? {};
            data['id'] = snapshot.id;
            data['eventId'] = eventId; // Ensure eventId is present
            data['orgId'] = orgId;
            return Attendee.fromMap(data, snapshot.id);
          },
          toFirestore: (attendee, _) {
            final json = attendee.toMap();
            json.remove('id');
            json.remove('eventId');
            // orgId IS stored (unlike id/eventId) — it's the denormalised
            // field the admin's cross-event collectionGroup query filters
            // on, see the class comment above.
            return json;
          },
        );
  }

  // ==========================================
  // FEEDBACK SUBCOLLECTION (org + event scoped)
  // ==========================================
  static CollectionReference<EventFeedback> feedback(String orgId, String eventId) {
    return _orgEvents(orgId)
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
