part of 'counter_bloc.dart';

/// Base class for all counter-related events.
sealed class CounterEvent {
  const CounterEvent();
}

/// User tapped increment button.
final class CounterIncrementPressed extends CounterEvent {
  const CounterIncrementPressed();
}

/// User tapped decrement button.
final class CounterDecrementPressed extends CounterEvent {
  const CounterDecrementPressed();
}
