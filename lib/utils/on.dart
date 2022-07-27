import 'entity_emitter.dart';

Destroyable on(EventEmitter obj, String ev, EventHandler fn) {
  obj.on(ev, fn);
  return Destroyable(() => obj.off(ev, fn));
}

class Destroyable {
  Function callback;
  Destroyable(this.callback);
  void destroy() => callback();
}
