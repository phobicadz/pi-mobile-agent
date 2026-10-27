import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pi_models.dart';
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
        viewModel.state?.currentModelProvider ?? '',
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
        final state = viewModel.state;
        final currentModel = state?.currentModel;

        // Pi can be running a model it never offered - a model its provider
        // stopped making available, for one, which is exactly the state that
        // makes every prompt fail. DropdownButton asserts that its value is one
        // of its items, so a current model missing from the list used to take
        // the whole input area down with it. Show it, marked as not offered, so
        // what is live is visible and one tap gets off it.
        final listed = List<PiModel>.from(models);
        if (currentModel != null &&
            !listed.any((model) => model.id == currentModel)) {
          listed.insert(
            0,
            PiModel(
              id: currentModel,
              name: '$currentModel (not offered)',
              provider: state?.currentModelProvider ?? '',
              available: false,
            ),
          );
        }

        if (listed.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Loading models...'),
          );
        }

        // A remembered choice that is no longer a choice falls back to what Pi
        // is actually using.
        final remembered = _selectedModel;
        final value =
            remembered != null && listed.any((model) => model.id == remembered)
                ? remembered
                : (currentModel != null &&
                        listed.any((model) => model.id == currentModel)
                    ? currentModel
                    : null);

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
            value: value,
            items: listed.map((model) {
              final offered = model.available;
              return DropdownMenuItem(
                value: model.id,
                child: Row(
                  children: [
                    Icon(
                      offered ? Icons.model_training : Icons.error_outline,
                      size: 16,
                      color: offered ? null : Colors.redAccent,
                    ),
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
              if (modelId == null) return;
              PiModel? chosen;
              for (final model in listed) {
                if (model.id == modelId) {
                  chosen = model;
                  break;
                }
              }
              if (chosen == null) return;
              setState(() => _selectedModel = modelId);
              viewModel.selectModel(chosen);
            },
          ),
        );
      },
    );
  }
}
