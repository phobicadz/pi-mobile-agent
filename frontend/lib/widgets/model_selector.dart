import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pi_view_model.dart';

class ModelSelector extends StatefulWidget {
  const ModelSelector({super.key});

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  String? _selectedModel;

  @override
  Widget build(BuildContext context) {
    // The dropdown is rebuilt only when the model list or the selected model
    // actually changes. A plain Consumer here rebuilt every model row on every
    // streamed token, while the chat was also re-rendering.
    return Selector<PiViewModel, String>(
      selector: (_, viewModel) => [
        viewModel.state?.currentModel ?? '',
        for (final model in viewModel.availableModels)
          '${model.id}:${model.name}:${model.provider}',
      ].join('|'),
      builder: (context, _, __) {
        final viewModel = context.read<PiViewModel>();
        if (viewModel.availableModels.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Loading models...'),
          );
        }

        final models = viewModel.availableModels;
        final currentModel = viewModel.state?.currentModel;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            isExpanded: true,
            underline: const SizedBox(),
            hint: const Text('Select a model'),
            value: _selectedModel ?? currentModel,
            items: models.map((model) {
              return DropdownMenuItem(
                value: model.id,
                child: Row(
                  children: [
                    const Icon(Icons.model_training, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            model.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            model.provider,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (modelId) {
              if (modelId != null) {
                setState(() => _selectedModel = modelId);
                viewModel.selectModel(modelId);
              }
            },
          ),
        );
      },
    );
  }
}
