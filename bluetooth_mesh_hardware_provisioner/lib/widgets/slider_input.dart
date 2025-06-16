// lib/widgets/slider_input.dart

import 'package:flutter/material.dart';

/// Combines a numeric text field with a slider.
/// The slider updates the text field as it moves.
class SliderInput extends StatefulWidget {
  final String label;
  final int min;
  final int max;
  final TextEditingController controller;

  const SliderInput({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.controller,
  });

  @override
  State<SliderInput> createState() => _SliderInputState();
}

class _SliderInputState extends State<SliderInput> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = double.tryParse(widget.controller.text) ?? widget.min.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: '${widget.min}-${widget.max}',
          ),
          onChanged: (text) {
            final v = double.tryParse(text);
            if (v != null) {
              setState(() => _value = v.clamp(widget.min.toDouble(), widget.max.toDouble()));
            }
          },
        ),
        Slider(
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          divisions: widget.max - widget.min,
          value: _value.clamp(widget.min.toDouble(), widget.max.toDouble()),
          label: _value.round().toString(),
          onChanged: (val) {
            setState(() {
              _value = val;
              widget.controller.text = val.round().toString();
            });
          },
        ),
      ],
    );
  }
}
