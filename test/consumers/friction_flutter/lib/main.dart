import 'package:flutter/material.dart';

void main() => runApp(const FrictionApp());

final class FrictionApp extends StatelessWidget {
  const FrictionApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(child: Text('Consumidor sem integracao DevExKit')),
    ),
  );
}
