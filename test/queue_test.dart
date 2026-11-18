import 'package:flutter_test/flutter_test.dart';

import 'package:andika/app/controller.dart';

QueuedItem item(String t) => QueuedItem(title: t, language: 'fr', modelId: 'base');

void main() {
  test('file d\'attente : ajout, retrait, vidage', () {
    final c = AppController();
    var notified = 0;
    c.addListener(() => notified++);
    final a = item('Entretien 1');
    final b = item('Entretien 2');
    c.enqueue(a);
    c.enqueue(b);
    expect(c.queue.map((i) => i.title), ['Entretien 1', 'Entretien 2']);
    c.removeFromQueue(a);
    expect(c.queue, [b]);
    c.queueHeld = true;
    c.removeFromQueue(b);
    expect(c.queue, isEmpty);
    expect(c.queueHeld, isFalse); // file vide : plus rien à suspendre
    c.enqueue(a);
    c.clearQueue();
    expect(c.queue, isEmpty);
    expect(notified, greaterThanOrEqualTo(5));
  });
}
