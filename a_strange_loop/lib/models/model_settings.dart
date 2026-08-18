class ModelSettings {
  final String model;
  final String thinkingEffort;

  static const defaultModel = 'mimo-v2.5';
  static const defaultThinking = 'low';

  static const modelOptions = [
    'mimo-v2.5',
    'mimo-v2.5-pro',
    'deepseek-v4-flash',
    'deepseek-v4-pro',
  ];
  static const thinkingOptions = ['disabled', 'low', 'high', 'max'];

  static bool isMimoModel(String model) => model.startsWith('mimo-');

  const ModelSettings({
    this.model = defaultModel,
    this.thinkingEffort = defaultThinking,
  });

  Map<String, dynamic> toJson() => {
        'model': model,
        'thinking_effort': thinkingEffort,
      };

  factory ModelSettings.fromJson(Map<String, dynamic> json) {
    return ModelSettings(
      model: (json['model'] as String?) ?? defaultModel,
      thinkingEffort:
          (json['thinking_effort'] as String?) ?? defaultThinking,
    );
  }

  Map<String, dynamic> get thinkingParam {
    if (thinkingEffort == 'disabled') {
      return {'type': 'disabled'};
    }
    return {'type': 'enabled'};
  }

  ModelSettings copyWith({String? model, String? thinkingEffort}) {
    return ModelSettings(
      model: model ?? this.model,
      thinkingEffort: thinkingEffort ?? this.thinkingEffort,
    );
  }
}
