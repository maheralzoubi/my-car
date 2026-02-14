part of 'counter_bloc.dart';

/// State for the counter feature.
final class CounterState {
  const CounterState({this.count = 0});

  final int count;

  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }
}
