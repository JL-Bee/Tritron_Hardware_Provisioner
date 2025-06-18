// lib/widgets/slider_input.dart

import 'package:flutter/material.dart';

/// Combines a numeric text field with a slider.
/// The slider updates the text field as it moves.
class SliderInput extends StatefulWidget {
  final String label;
  final int min;
  final int max;
  final int sliderMax;
  final TextEditingController controller;

  /// Creates a [SliderInput].
  ///
  /// [min] and [max] define the valid range for the text input field while
  /// [sliderMax] controls the maximum value of the slider itself. When
  /// [sliderMax] is not provided it defaults to [max].
  const SliderInput({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.controller,
    int? sliderMax,
  }) : sliderMax = sliderMax ?? max;

  @override
  State<SliderInput> createState() => _SliderInputState();
}

class _SliderInputState extends State<SliderInput> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = (double.tryParse(widget.controller.text) ?? widget.min.toDouble())
        .clamp(widget.min.toDouble(), widget.sliderMax.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: '${widget.min}-${widget.max}',
              helperText: '${widget.min}-${widget.max}',
            ),
            onChanged: (text) {
              final v = double.tryParse(text);
              if (v != null) {
                setState(() => _value =
                    v.clamp(widget.min.toDouble(), widget.sliderMax.toDouble()));
              }
            },
          ),
          Slider(
            min: widget.min.toDouble(),
            max: widget.sliderMax.toDouble(),
            divisions: widget.sliderMax - widget.min,
            value:
                _value.clamp(widget.min.toDouble(), widget.sliderMax.toDouble()),
            label: _value.round().toString(),
            onChanged: (val) {
              setState(() {
                _value = val;
                widget.controller.text = val.round().toString();
              });
            },
          ),
        ],
      ),
    );
  }
}
