import 'dart:collection' show HashMap;

typedef EventHandler<T> = dynamic Function(T data);

class EventEmitter {
  Map<String, List<EventHandler>> _events =
      HashMap<String, List<EventHandler>>();

  Map<String, List<EventHandler>> _eventsOnce =
      HashMap<String, List<EventHandler>>();

  EventEmitter();

  void emit(String event, [dynamic data]) {
    final list0 = _events[event];

    final list = list0 != null ? List.from(list0) : null;
    list?.forEach((handler) {
      handler(data);
    });

    _eventsOnce.remove(event)?.forEach((EventHandler handler) {
      handler(data);
    });
  }

  void on(String event, EventHandler handler) {
    _events.putIfAbsent(event, () => <EventHandler>[]);
    _events[event]!.add(handler);
  }

  void once(String event, EventHandler handler) {
    _eventsOnce.putIfAbsent(event, () => <EventHandler>[]);
    _eventsOnce[event]!.add(handler);
  }

  void off(String event, [EventHandler? handler]) {
    if (handler != null) {
      _events[event]?.remove(handler);
      _eventsOnce[event]?.remove(handler);
      if (_events[event]?.isEmpty == true) {
        _events.remove(event);
      }
      if (_eventsOnce[event]?.isEmpty == true) {
        _eventsOnce.remove(event);
      }
    } else {
      _events.remove(event);
      _eventsOnce.remove(event);
    }
  }

  void clearListeners() {
    _events = HashMap<String, List<EventHandler>>();
    _eventsOnce = HashMap<String, List<EventHandler>>();
  }

  bool hasListeners(String event) {
    return _events[event]?.isNotEmpty == true ||
        _eventsOnce[event]?.isNotEmpty == true;
  }
}
