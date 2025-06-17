// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/provisioner_bloc.dart';
import 'screens/main_screen.dart';

void main() {
  runZonedGuarded(
    () => runApp(const BlocProvisionerApp()),
    (error, stack) => print('Unhandled exception: $error'),
  );
}

class BlocProvisionerApp extends StatelessWidget {
  const BlocProvisionerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProvisionerBloc(),
      child: MaterialApp(
        title: 'Remoticom Bluetooth Mesh Provisioner',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
          dialogTheme: const DialogThemeData(surfaceTintColor: Colors.transparent),
          appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
          dialogTheme: const DialogThemeData(surfaceTintColor: Colors.transparent),
          appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
        ),
        debugShowCheckedModeBanner: false,
        home: const BlocMainScreen(),
      ),
    );
  }
}
