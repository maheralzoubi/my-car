import 'package:flutter/material.dart';

enum ServiceType {
  flatbedTowing,
  batteryJump,
  tireRepair,
  carTowing,
  batteryReplacement,
  fuelDelivery,
}

extension ServiceTypeX on ServiceType {
  String get label {
    switch (this) {
      case ServiceType.flatbedTowing:
        return 'Flatbed Towing';
      case ServiceType.batteryJump:
        return 'Battery Jump';
      case ServiceType.tireRepair:
        return 'Tire Repair';
      case ServiceType.carTowing:
        return 'Car Towing';
      case ServiceType.batteryReplacement:
        return 'Battery Replacement';
      case ServiceType.fuelDelivery:
        return 'Fuel Delivery';
    }
  }

  String get description {
    switch (this) {
      case ServiceType.flatbedTowing:
        return 'Vehicle transport on flat carrier';
      case ServiceType.batteryJump:
        return 'Jump start your dead battery';
      case ServiceType.tireRepair:
        return 'Fix or replace a flat tire';
      case ServiceType.carTowing:
        return 'Tow to the nearest garage';
      case ServiceType.batteryReplacement:
        return 'New battery installed on-site';
      case ServiceType.fuelDelivery:
        return 'Emergency fuel to your location';
    }
  }

  IconData get icon {
    switch (this) {
      case ServiceType.flatbedTowing:
        return Icons.local_shipping_rounded;
      case ServiceType.batteryJump:
        return Icons.battery_charging_full_rounded;
      case ServiceType.tireRepair:
        return Icons.tire_repair;
      case ServiceType.carTowing:
        return Icons.directions_car_rounded;
      case ServiceType.batteryReplacement:
        return Icons.battery_full_rounded;
      case ServiceType.fuelDelivery:
        return Icons.local_gas_station_rounded;
    }
  }

  double get basePrice {
    switch (this) {
      case ServiceType.flatbedTowing:
        return 150.0;
      case ServiceType.batteryJump:
        return 65.0;
      case ServiceType.tireRepair:
        return 55.0;
      case ServiceType.carTowing:
        return 100.0;
      case ServiceType.batteryReplacement:
        return 130.0;
      case ServiceType.fuelDelivery:
        return 45.0;
    }
  }

  int get etaMinutes {
    switch (this) {
      case ServiceType.flatbedTowing:
        return 25;
      case ServiceType.batteryJump:
        return 15;
      case ServiceType.tireRepair:
        return 20;
      case ServiceType.carTowing:
        return 20;
      case ServiceType.batteryReplacement:
        return 30;
      case ServiceType.fuelDelivery:
        return 18;
    }
  }

  Color get color {
    switch (this) {
      case ServiceType.flatbedTowing:
        return const Color(0xFFFF6B35);
      case ServiceType.batteryJump:
        return const Color(0xFF00D9FF);
      case ServiceType.tireRepair:
        return const Color(0xFF4CAF50);
      case ServiceType.carTowing:
        return const Color(0xFFFF9800);
      case ServiceType.batteryReplacement:
        return const Color(0xFF9C27B0);
      case ServiceType.fuelDelivery:
        return const Color(0xFFF44336);
    }
  }
}
