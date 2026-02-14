import 'package:bloc/bloc.dart';

part 'counter_event.dart';
part 'counter_state.dart';

/// BLoC that manages counter business logic on the home screen.
class CounterBloc extends Bloc<CounterEvent, CounterState> {
  CounterBloc() : super(const CounterState()) {
    on<CounterIncrementPressed>(_onIncrement);
    on<CounterDecrementPressed>(_onDecrement);
  }

  void _onIncrement(
    CounterIncrementPressed event,
    Emitter<CounterState> emit,
  ) {
    emit(state.copyWith(count: state.count + 1));
  }

  void _onDecrement(
    CounterDecrementPressed event,
    Emitter<CounterState> emit,
  ) {
    emit(state.copyWith(count: state.count - 1));
  }
}
