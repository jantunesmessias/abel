import '../composition/kit_composition_contracts.dart';
import '../digest.dart';
import '../evidence/android_evidence_contracts.dart';
import '../evidence/evidence_contracts.dart';
import '../preview/preview_contracts.dart';
import '../sessions/session_contracts.dart';
import 'catalog_contracts.dart';

final class AppAdapterCapabilityId extends OpaqueId {
  factory AppAdapterCapabilityId(String value) {
    _labId(value, 'AppAdapterCapability');
    return AppAdapterCapabilityId._(value);
  }

  const AppAdapterCapabilityId._(super.value);
}

final class CapabilityOperationId extends OpaqueId {
  factory CapabilityOperationId(String value) {
    _labId(value, 'CapabilityOperation');
    return CapabilityOperationId._(value);
  }

  const CapabilityOperationId._(super.value);
}

final class ScenarioControlId extends OpaqueId {
  factory ScenarioControlId(String value) {
    _labId(value, 'ScenarioControl');
    return ScenarioControlId._(value);
  }

  const ScenarioControlId._(super.value);
}

final class ControlChoiceId extends OpaqueId {
  factory ControlChoiceId(String value) {
    _labId(value, 'ControlChoice');
    return ControlChoiceId._(value);
  }

  const ControlChoiceId._(super.value);
}

final class ScenarioLabOperationId extends OpaqueId {
  factory ScenarioLabOperationId(String value) {
    _labId(value, 'ScenarioLabOperation');
    return ScenarioLabOperationId._(value);
  }

  const ScenarioLabOperationId._(super.value);
}

final class ScenarioScriptId extends OpaqueId {
  factory ScenarioScriptId(String value) {
    _labId(value, 'ScenarioScript');
    return ScenarioScriptId._(value);
  }

  const ScenarioScriptId._(super.value);
}

final class AutomatedAcceptanceCriterionId extends OpaqueId {
  factory AutomatedAcceptanceCriterionId(String value) {
    _labId(value, 'AutomatedAcceptanceCriterion');
    return AutomatedAcceptanceCriterionId._(value);
  }

  const AutomatedAcceptanceCriterionId._(super.value);
}

final class RequiredEvidenceId extends OpaqueId {
  factory RequiredEvidenceId(String value) {
    _labId(value, 'RequiredEvidence');
    return RequiredEvidenceId._(value);
  }

  const RequiredEvidenceId._(super.value);
}

final class EvidencePolicyId extends OpaqueId {
  factory EvidencePolicyId(String value) {
    _labId(value, 'EvidencePolicy');
    return EvidencePolicyId._(value);
  }

  const EvidencePolicyId._(super.value);
}

final class VisualComparisonPolicyId extends OpaqueId {
  factory VisualComparisonPolicyId(String value) {
    _labId(value, 'VisualComparisonPolicy');
    return VisualComparisonPolicyId._(value);
  }

  const VisualComparisonPolicyId._(super.value);
}

final class SemanticComparisonPolicyId extends OpaqueId {
  factory SemanticComparisonPolicyId(String value) {
    _labId(value, 'SemanticComparisonPolicy');
    return SemanticComparisonPolicyId._(value);
  }

  const SemanticComparisonPolicyId._(super.value);
}

final class HumanApprovalRequirementId extends OpaqueId {
  factory HumanApprovalRequirementId(String value) {
    _labId(value, 'HumanApprovalRequirement');
    return HumanApprovalRequirementId._(value);
  }

  const HumanApprovalRequirementId._(super.value);
}

final class SupplementalArtifactId extends OpaqueId {
  factory SupplementalArtifactId(String value) {
    _labId(value, 'SupplementalArtifact');
    return SupplementalArtifactId._(value);
  }

  const SupplementalArtifactId._(super.value);
}

final class ScenarioComparisonBindingId extends OpaqueId {
  factory ScenarioComparisonBindingId(String value) {
    _labId(value, 'ScenarioComparisonBinding');
    return ScenarioComparisonBindingId._(value);
  }

  const ScenarioComparisonBindingId._(super.value);
}

enum ScenarioControlValueKind { boolean, choice, integer }

enum ScenarioControlDomainKind { boolean, choice, integerRange }

enum ScenarioLabOperationKind { assignControl, resetControl, collectEvidence }

enum ScenarioScriptStepKind { operation, executionBinding }

enum ScenarioScriptCancellationPolicy { immediate, afterCurrentStep }

enum ScenarioScriptTimeoutOutcome { fail, cancel }

enum AutomatedAcceptanceCriterionKind {
  scriptSucceeded,
  evidenceAccepted,
  controlEquals,
}

enum ComparisonPolicyKind { visual, semantic }

enum HumanApprovalScope { scenarioRun, evidenceSet }

enum ComparisonInputKind { artifact, evidence, requiredEvidence }

enum SupplementalArtifactRole {
  comparisonBaseline,
  comparisonCandidate,
  diagnostic,
}

final class AppAdapterCapabilityReference {
  AppAdapterCapabilityReference({required this.id, required this.version}) {
    if (version < 1 || version > 1000000) {
      throw ArgumentError.value(
        version,
        'version',
        'must be between 1 and 1000000',
      );
    }
  }

  final AppAdapterCapabilityId id;
  final int version;

  String get key => '${id.value}@$version';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'version': version,
  };

  factory AppAdapterCapabilityReference.fromJson(Object? value) {
    final json = _labObject(value, 'AppAdapterCapabilityReference');
    _labOnly(json, const <String>{
      'id',
      'version',
    }, 'AppAdapterCapabilityReference');
    return AppAdapterCapabilityReference(
      id: AppAdapterCapabilityId(
        _labString(json, 'id', 'AppAdapterCapabilityReference'),
      ),
      version: _labInteger(json, 'version', 'AppAdapterCapabilityReference'),
    );
  }
}

sealed class ScenarioControlValue {
  const ScenarioControlValue();

  ScenarioControlValueKind get kind;

  Object get value;

  Map<String, Object?> toJson();

  factory ScenarioControlValue.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioControlValue');
    final kind = _labEnum(
      ScenarioControlValueKind.values,
      _labString(json, 'kind', 'ScenarioControlValue'),
      'ScenarioControlValue.kind',
    );
    return switch (kind) {
      ScenarioControlValueKind.boolean => BooleanScenarioControlValue.fromJson(
        json,
      ),
      ScenarioControlValueKind.choice => ChoiceScenarioControlValue.fromJson(
        json,
      ),
      ScenarioControlValueKind.integer => IntegerScenarioControlValue.fromJson(
        json,
      ),
    };
  }
}

final class BooleanScenarioControlValue extends ScenarioControlValue {
  const BooleanScenarioControlValue(this.value);

  @override
  final bool value;

  @override
  ScenarioControlValueKind get kind => ScenarioControlValueKind.boolean;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'value': value,
  };

  factory BooleanScenarioControlValue.fromJson(Object? value) {
    final json = _labObject(value, 'BooleanScenarioControlValue');
    _labOnly(json, const <String>{
      'kind',
      'value',
    }, 'BooleanScenarioControlValue');
    if (json['kind'] != ScenarioControlValueKind.boolean.name ||
        json['value'] is! bool) {
      throw const FormatException('Invalid BooleanScenarioControlValue');
    }
    return BooleanScenarioControlValue(json['value']! as bool);
  }
}

final class ChoiceScenarioControlValue extends ScenarioControlValue {
  const ChoiceScenarioControlValue(this.value);

  @override
  final ControlChoiceId value;

  @override
  ScenarioControlValueKind get kind => ScenarioControlValueKind.choice;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'value': value.value,
  };

  factory ChoiceScenarioControlValue.fromJson(Object? value) {
    final json = _labObject(value, 'ChoiceScenarioControlValue');
    _labOnly(json, const <String>{
      'kind',
      'value',
    }, 'ChoiceScenarioControlValue');
    if (json['kind'] != ScenarioControlValueKind.choice.name) {
      throw const FormatException('Invalid ChoiceScenarioControlValue kind');
    }
    return ChoiceScenarioControlValue(
      ControlChoiceId(_labString(json, 'value', 'ChoiceScenarioControlValue')),
    );
  }
}

final class IntegerScenarioControlValue extends ScenarioControlValue {
  const IntegerScenarioControlValue(this.value);

  @override
  final int value;

  @override
  ScenarioControlValueKind get kind => ScenarioControlValueKind.integer;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'value': value,
  };

  factory IntegerScenarioControlValue.fromJson(Object? value) {
    final json = _labObject(value, 'IntegerScenarioControlValue');
    _labOnly(json, const <String>{
      'kind',
      'value',
    }, 'IntegerScenarioControlValue');
    if (json['kind'] != ScenarioControlValueKind.integer.name ||
        json['value'] is! int) {
      throw const FormatException('Invalid IntegerScenarioControlValue');
    }
    return IntegerScenarioControlValue(json['value']! as int);
  }
}

final class ScenarioControlChoice {
  ScenarioControlChoice({required this.id, required this.displayName}) {
    _labText(displayName, 'ScenarioControlChoice.displayName', maxLength: 512);
  }

  final ControlChoiceId id;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'displayName': displayName,
  };

  factory ScenarioControlChoice.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioControlChoice');
    _labOnly(json, const <String>{
      'id',
      'displayName',
    }, 'ScenarioControlChoice');
    return ScenarioControlChoice(
      id: ControlChoiceId(_labString(json, 'id', 'ScenarioControlChoice')),
      displayName: _labString(
        json,
        'displayName',
        'ScenarioControlChoice',
        maxLength: 512,
      ),
    );
  }
}

sealed class ScenarioControlDomain {
  const ScenarioControlDomain();

  ScenarioControlDomainKind get kind;

  ScenarioControlValue get defaultValue;

  bool accepts(ScenarioControlValue value);

  Map<String, Object?> toJson();

  factory ScenarioControlDomain.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioControlDomain');
    final kind = _labEnum(
      ScenarioControlDomainKind.values,
      _labString(json, 'kind', 'ScenarioControlDomain'),
      'ScenarioControlDomain.kind',
    );
    return switch (kind) {
      ScenarioControlDomainKind.boolean =>
        BooleanScenarioControlDomain.fromJson(json),
      ScenarioControlDomainKind.choice => ChoiceScenarioControlDomain.fromJson(
        json,
      ),
      ScenarioControlDomainKind.integerRange =>
        IntegerRangeScenarioControlDomain.fromJson(json),
    };
  }
}

final class BooleanScenarioControlDomain extends ScenarioControlDomain {
  BooleanScenarioControlDomain({required bool defaultValue})
    : defaultValue = BooleanScenarioControlValue(defaultValue);

  @override
  final BooleanScenarioControlValue defaultValue;

  @override
  ScenarioControlDomainKind get kind => ScenarioControlDomainKind.boolean;

  @override
  bool accepts(ScenarioControlValue value) =>
      value is BooleanScenarioControlValue;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'defaultValue': defaultValue.value,
  };

  factory BooleanScenarioControlDomain.fromJson(Object? value) {
    final json = _labObject(value, 'BooleanScenarioControlDomain');
    _labOnly(json, const <String>{
      'kind',
      'defaultValue',
    }, 'BooleanScenarioControlDomain');
    if (json['kind'] != ScenarioControlDomainKind.boolean.name ||
        json['defaultValue'] is! bool) {
      throw const FormatException('Invalid BooleanScenarioControlDomain');
    }
    return BooleanScenarioControlDomain(
      defaultValue: json['defaultValue']! as bool,
    );
  }
}

final class ChoiceScenarioControlDomain extends ScenarioControlDomain {
  ChoiceScenarioControlDomain({
    required ControlChoiceId defaultValue,
    required Iterable<ScenarioControlChoice> choices,
  }) : defaultValue = ChoiceScenarioControlValue(defaultValue),
       choices = List<ScenarioControlChoice>.unmodifiable(choices) {
    if (this.choices.isEmpty || this.choices.length > 256) {
      throw ArgumentError('Choice control requires between 1 and 256 choices');
    }
    final ids = this.choices.map((choice) => choice.id).toList(growable: false);
    if (ids.toSet().length != ids.length || !ids.contains(defaultValue)) {
      throw ArgumentError('Choice control choices/default are invalid');
    }
  }

  @override
  final ChoiceScenarioControlValue defaultValue;
  final List<ScenarioControlChoice> choices;

  @override
  ScenarioControlDomainKind get kind => ScenarioControlDomainKind.choice;

  @override
  bool accepts(ScenarioControlValue value) =>
      value is ChoiceScenarioControlValue &&
      choices.any((choice) => choice.id == value.value);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'defaultValue': defaultValue.value.value,
    'choices': choices.map((choice) => choice.toJson()).toList(),
  };

  factory ChoiceScenarioControlDomain.fromJson(Object? value) {
    final json = _labObject(value, 'ChoiceScenarioControlDomain');
    _labOnly(json, const <String>{
      'kind',
      'defaultValue',
      'choices',
    }, 'ChoiceScenarioControlDomain');
    if (json['kind'] != ScenarioControlDomainKind.choice.name) {
      throw const FormatException('Invalid ChoiceScenarioControlDomain kind');
    }
    return ChoiceScenarioControlDomain(
      defaultValue: ControlChoiceId(
        _labString(json, 'defaultValue', 'ChoiceScenarioControlDomain'),
      ),
      choices: _labList(
        json,
        'choices',
        'ChoiceScenarioControlDomain',
        minItems: 1,
        maxItems: 256,
      ).map(ScenarioControlChoice.fromJson),
    );
  }
}

final class IntegerRangeScenarioControlDomain extends ScenarioControlDomain {
  IntegerRangeScenarioControlDomain({
    required int defaultValue,
    required this.minimum,
    required this.maximum,
    required this.step,
  }) : defaultValue = IntegerScenarioControlValue(defaultValue) {
    if (minimum < -1000000 ||
        maximum > 1000000 ||
        minimum > maximum ||
        step < 1 ||
        step > 1000000 ||
        defaultValue < minimum ||
        defaultValue > maximum ||
        (defaultValue - minimum) % step != 0) {
      throw ArgumentError('Integer control range/default/step are invalid');
    }
  }

  @override
  final IntegerScenarioControlValue defaultValue;
  final int minimum;
  final int maximum;
  final int step;

  @override
  ScenarioControlDomainKind get kind => ScenarioControlDomainKind.integerRange;

  @override
  bool accepts(ScenarioControlValue value) =>
      value is IntegerScenarioControlValue &&
      value.value >= minimum &&
      value.value <= maximum &&
      (value.value - minimum) % step == 0;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'defaultValue': defaultValue.value,
    'minimum': minimum,
    'maximum': maximum,
    'step': step,
  };

  factory IntegerRangeScenarioControlDomain.fromJson(Object? value) {
    final json = _labObject(value, 'IntegerRangeScenarioControlDomain');
    _labOnly(json, const <String>{
      'kind',
      'defaultValue',
      'minimum',
      'maximum',
      'step',
    }, 'IntegerRangeScenarioControlDomain');
    if (json['kind'] != ScenarioControlDomainKind.integerRange.name) {
      throw const FormatException(
        'Invalid IntegerRangeScenarioControlDomain kind',
      );
    }
    return IntegerRangeScenarioControlDomain(
      defaultValue: _labInteger(
        json,
        'defaultValue',
        'IntegerRangeScenarioControlDomain',
      ),
      minimum: _labInteger(
        json,
        'minimum',
        'IntegerRangeScenarioControlDomain',
      ),
      maximum: _labInteger(
        json,
        'maximum',
        'IntegerRangeScenarioControlDomain',
      ),
      step: _labInteger(json, 'step', 'IntegerRangeScenarioControlDomain'),
    );
  }
}

final class ScenarioControlDefinition {
  ScenarioControlDefinition({
    required this.id,
    required this.scenarioId,
    required this.displayName,
    required this.capability,
    required this.readOperationId,
    required this.writeOperationId,
    this.resetOperationId,
    required this.domain,
  }) {
    _labText(
      displayName,
      'ScenarioControlDefinition.displayName',
      maxLength: 512,
    );
    final operations = <CapabilityOperationId>{
      readOperationId,
      writeOperationId,
      ?resetOperationId,
    };
    final expected = resetOperationId == null ? 2 : 3;
    if (operations.length != expected) {
      throw ArgumentError('ScenarioControl operations must be distinct');
    }
  }

  final ScenarioControlId id;
  final ScenarioId scenarioId;
  final String displayName;
  final AppAdapterCapabilityReference capability;
  final CapabilityOperationId readOperationId;
  final CapabilityOperationId writeOperationId;
  final CapabilityOperationId? resetOperationId;
  final ScenarioControlDomain domain;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'displayName': displayName,
    'capability': capability.toJson(),
    'readOperationId': readOperationId.value,
    'writeOperationId': writeOperationId.value,
    if (resetOperationId != null) 'resetOperationId': resetOperationId!.value,
    'domain': domain.toJson(),
  };

  factory ScenarioControlDefinition.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioControlDefinition');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'displayName',
      'capability',
      'readOperationId',
      'writeOperationId',
      'resetOperationId',
      'domain',
    }, 'ScenarioControlDefinition');
    final reset = _labOptionalString(
      json,
      'resetOperationId',
      'ScenarioControlDefinition',
    );
    return ScenarioControlDefinition(
      id: ScenarioControlId(
        _labString(json, 'id', 'ScenarioControlDefinition'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'ScenarioControlDefinition'),
      ),
      displayName: _labString(
        json,
        'displayName',
        'ScenarioControlDefinition',
        maxLength: 512,
      ),
      capability: AppAdapterCapabilityReference.fromJson(json['capability']),
      readOperationId: CapabilityOperationId(
        _labString(json, 'readOperationId', 'ScenarioControlDefinition'),
      ),
      writeOperationId: CapabilityOperationId(
        _labString(json, 'writeOperationId', 'ScenarioControlDefinition'),
      ),
      resetOperationId: reset == null ? null : CapabilityOperationId(reset),
      domain: ScenarioControlDomain.fromJson(json['domain']),
    );
  }
}

sealed class ComparisonPolicyReference {
  const ComparisonPolicyReference();

  ComparisonPolicyKind get kind;

  String get policyId;

  Map<String, Object?> toJson();

  factory ComparisonPolicyReference.fromJson(Object? value) {
    final json = _labObject(value, 'ComparisonPolicyReference');
    final kind = _labEnum(
      ComparisonPolicyKind.values,
      _labString(json, 'kind', 'ComparisonPolicyReference'),
      'ComparisonPolicyReference.kind',
    );
    return switch (kind) {
      ComparisonPolicyKind.visual => VisualComparisonPolicyReference.fromJson(
        json,
      ),
      ComparisonPolicyKind.semantic =>
        SemanticComparisonPolicyReference.fromJson(json),
    };
  }
}

final class VisualComparisonPolicyReference extends ComparisonPolicyReference {
  const VisualComparisonPolicyReference(this.id);

  final VisualComparisonPolicyId id;

  @override
  ComparisonPolicyKind get kind => ComparisonPolicyKind.visual;

  @override
  String get policyId => id.value;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'policyId': id.value,
  };

  factory VisualComparisonPolicyReference.fromJson(Object? value) {
    final json = _labObject(value, 'VisualComparisonPolicyReference');
    _labOnly(json, const <String>{
      'kind',
      'policyId',
    }, 'VisualComparisonPolicyReference');
    if (json['kind'] != ComparisonPolicyKind.visual.name) {
      throw const FormatException('Invalid visual policy reference kind');
    }
    return VisualComparisonPolicyReference(
      VisualComparisonPolicyId(
        _labString(json, 'policyId', 'VisualComparisonPolicyReference'),
      ),
    );
  }
}

final class SemanticComparisonPolicyReference
    extends ComparisonPolicyReference {
  const SemanticComparisonPolicyReference(this.id);

  final SemanticComparisonPolicyId id;

  @override
  ComparisonPolicyKind get kind => ComparisonPolicyKind.semantic;

  @override
  String get policyId => id.value;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'policyId': id.value,
  };

  factory SemanticComparisonPolicyReference.fromJson(Object? value) {
    final json = _labObject(value, 'SemanticComparisonPolicyReference');
    _labOnly(json, const <String>{
      'kind',
      'policyId',
    }, 'SemanticComparisonPolicyReference');
    if (json['kind'] != ComparisonPolicyKind.semantic.name) {
      throw const FormatException('Invalid semantic policy reference kind');
    }
    return SemanticComparisonPolicyReference(
      SemanticComparisonPolicyId(
        _labString(json, 'policyId', 'SemanticComparisonPolicyReference'),
      ),
    );
  }
}

final class RequiredEvidenceDefinition {
  RequiredEvidenceDefinition({
    required this.id,
    required this.scenarioId,
    required this.providerId,
    required this.fidelity,
    required this.variantId,
    required this.freshness,
    required Set<ArtifactClassification> allowedClassifications,
    required this.evidencePolicyId,
    required this.comparisonPolicy,
  }) : allowedClassifications = Set<ArtifactClassification>.unmodifiable(
         allowedClassifications,
       ) {
    if (freshness != EvidenceFreshness.fresh) {
      throw ArgumentError('Required Evidence must require fresh Evidence');
    }
    if (this.allowedClassifications.isEmpty ||
        this.allowedClassifications.length >
            ArtifactClassification.values.length) {
      throw ArgumentError('Required Evidence classifications are invalid');
    }
  }

  final RequiredEvidenceId id;
  final ScenarioId scenarioId;
  final ModuleId providerId;
  final RuntimeFidelity fidelity;
  final VariantId variantId;
  final EvidenceFreshness freshness;
  final Set<ArtifactClassification> allowedClassifications;
  final EvidencePolicyId evidencePolicyId;
  final ComparisonPolicyReference comparisonPolicy;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'providerId': providerId.value,
    'fidelity': fidelity.name,
    'variantId': variantId.value,
    'freshness': freshness.name,
    'allowedClassifications':
        allowedClassifications.map((value) => value.name).toList()..sort(),
    'evidencePolicyId': evidencePolicyId.value,
    'comparisonPolicy': comparisonPolicy.toJson(),
  };

  factory RequiredEvidenceDefinition.fromJson(Object? value) {
    final json = _labObject(value, 'RequiredEvidenceDefinition');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'providerId',
      'fidelity',
      'variantId',
      'freshness',
      'allowedClassifications',
      'evidencePolicyId',
      'comparisonPolicy',
    }, 'RequiredEvidenceDefinition');
    return RequiredEvidenceDefinition(
      id: RequiredEvidenceId(
        _labString(json, 'id', 'RequiredEvidenceDefinition'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'RequiredEvidenceDefinition'),
      ),
      providerId: ModuleId(
        _labString(json, 'providerId', 'RequiredEvidenceDefinition'),
      ),
      fidelity: _labEnum(
        RuntimeFidelity.values,
        _labString(json, 'fidelity', 'RequiredEvidenceDefinition'),
        'RequiredEvidenceDefinition.fidelity',
      ),
      variantId: VariantId(
        _labString(json, 'variantId', 'RequiredEvidenceDefinition'),
      ),
      freshness: _labEnum(
        EvidenceFreshness.values,
        _labString(json, 'freshness', 'RequiredEvidenceDefinition'),
        'RequiredEvidenceDefinition.freshness',
      ),
      allowedClassifications:
          _labStringList(
                json,
                'allowedClassifications',
                'RequiredEvidenceDefinition',
                minItems: 1,
                maxItems: ArtifactClassification.values.length,
              )
              .map(
                (name) => _labEnum(
                  ArtifactClassification.values,
                  name,
                  'RequiredEvidenceDefinition.allowedClassifications',
                ),
              )
              .toSet(),
      evidencePolicyId: EvidencePolicyId(
        _labString(json, 'evidencePolicyId', 'RequiredEvidenceDefinition'),
      ),
      comparisonPolicy: ComparisonPolicyReference.fromJson(
        json['comparisonPolicy'],
      ),
    );
  }
}

sealed class ScenarioLabOperationDefinition {
  const ScenarioLabOperationDefinition();

  ScenarioLabOperationId get id;

  ScenarioId get scenarioId;

  ScenarioLabOperationKind get kind;

  Map<String, Object?> toJson();

  factory ScenarioLabOperationDefinition.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioLabOperationDefinition');
    final kind = _labEnum(
      ScenarioLabOperationKind.values,
      _labString(json, 'kind', 'ScenarioLabOperationDefinition'),
      'ScenarioLabOperationDefinition.kind',
    );
    return switch (kind) {
      ScenarioLabOperationKind.assignControl =>
        AssignControlOperationDefinition.fromJson(json),
      ScenarioLabOperationKind.resetControl =>
        ResetControlOperationDefinition.fromJson(json),
      ScenarioLabOperationKind.collectEvidence =>
        CollectEvidenceOperationDefinition.fromJson(json),
    };
  }
}

final class AssignControlOperationDefinition
    extends ScenarioLabOperationDefinition {
  const AssignControlOperationDefinition({
    required this.id,
    required this.scenarioId,
    required this.controlId,
    required this.value,
  });

  @override
  final ScenarioLabOperationId id;
  @override
  final ScenarioId scenarioId;
  final ScenarioControlId controlId;
  final ScenarioControlValue value;

  @override
  ScenarioLabOperationKind get kind => ScenarioLabOperationKind.assignControl;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'kind': kind.name,
    'controlId': controlId.value,
    'value': value.toJson(),
  };

  factory AssignControlOperationDefinition.fromJson(Object? value) {
    final json = _labObject(value, 'AssignControlOperationDefinition');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'kind',
      'controlId',
      'value',
    }, 'AssignControlOperationDefinition');
    if (json['kind'] != ScenarioLabOperationKind.assignControl.name) {
      throw const FormatException('Invalid assign-control operation kind');
    }
    return AssignControlOperationDefinition(
      id: ScenarioLabOperationId(
        _labString(json, 'id', 'AssignControlOperationDefinition'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'AssignControlOperationDefinition'),
      ),
      controlId: ScenarioControlId(
        _labString(json, 'controlId', 'AssignControlOperationDefinition'),
      ),
      value: ScenarioControlValue.fromJson(json['value']),
    );
  }
}

final class ResetControlOperationDefinition
    extends ScenarioLabOperationDefinition {
  const ResetControlOperationDefinition({
    required this.id,
    required this.scenarioId,
    required this.controlId,
  });

  @override
  final ScenarioLabOperationId id;
  @override
  final ScenarioId scenarioId;
  final ScenarioControlId controlId;

  @override
  ScenarioLabOperationKind get kind => ScenarioLabOperationKind.resetControl;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'kind': kind.name,
    'controlId': controlId.value,
  };

  factory ResetControlOperationDefinition.fromJson(Object? value) {
    final json = _labObject(value, 'ResetControlOperationDefinition');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'kind',
      'controlId',
    }, 'ResetControlOperationDefinition');
    if (json['kind'] != ScenarioLabOperationKind.resetControl.name) {
      throw const FormatException('Invalid reset-control operation kind');
    }
    return ResetControlOperationDefinition(
      id: ScenarioLabOperationId(
        _labString(json, 'id', 'ResetControlOperationDefinition'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'ResetControlOperationDefinition'),
      ),
      controlId: ScenarioControlId(
        _labString(json, 'controlId', 'ResetControlOperationDefinition'),
      ),
    );
  }
}

final class CollectEvidenceOperationDefinition
    extends ScenarioLabOperationDefinition {
  const CollectEvidenceOperationDefinition({
    required this.id,
    required this.scenarioId,
    required this.evidenceRequirementId,
  });

  @override
  final ScenarioLabOperationId id;
  @override
  final ScenarioId scenarioId;
  final RequiredEvidenceId evidenceRequirementId;

  @override
  ScenarioLabOperationKind get kind => ScenarioLabOperationKind.collectEvidence;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'kind': kind.name,
    'evidenceRequirementId': evidenceRequirementId.value,
  };

  factory CollectEvidenceOperationDefinition.fromJson(Object? value) {
    final json = _labObject(value, 'CollectEvidenceOperationDefinition');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'kind',
      'evidenceRequirementId',
    }, 'CollectEvidenceOperationDefinition');
    if (json['kind'] != ScenarioLabOperationKind.collectEvidence.name) {
      throw const FormatException('Invalid collect-evidence operation kind');
    }
    return CollectEvidenceOperationDefinition(
      id: ScenarioLabOperationId(
        _labString(json, 'id', 'CollectEvidenceOperationDefinition'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'CollectEvidenceOperationDefinition'),
      ),
      evidenceRequirementId: RequiredEvidenceId(
        _labString(
          json,
          'evidenceRequirementId',
          'CollectEvidenceOperationDefinition',
        ),
      ),
    );
  }
}

sealed class ScenarioScriptStep {
  ScenarioScriptStep({
    required this.id,
    required this.timeoutMs,
    required this.timeoutOutcome,
  }) {
    _labId(id, 'ScenarioScriptStep');
    if (timeoutMs < 1 || timeoutMs > 300000) {
      throw ArgumentError.value(
        timeoutMs,
        'timeoutMs',
        'must be between 1 and 300000',
      );
    }
  }

  final String id;
  final int timeoutMs;
  final ScenarioScriptTimeoutOutcome timeoutOutcome;

  ScenarioScriptStepKind get kind;

  Map<String, Object?> toJson();

  factory ScenarioScriptStep.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioScriptStep');
    final kind = _labEnum(
      ScenarioScriptStepKind.values,
      _labString(json, 'kind', 'ScenarioScriptStep'),
      'ScenarioScriptStep.kind',
    );
    return switch (kind) {
      ScenarioScriptStepKind.operation => OperationScenarioScriptStep.fromJson(
        json,
      ),
      ScenarioScriptStepKind.executionBinding =>
        ExecutionBindingScenarioScriptStep.fromJson(json),
    };
  }
}

final class OperationScenarioScriptStep extends ScenarioScriptStep {
  OperationScenarioScriptStep({
    required super.id,
    required super.timeoutMs,
    required super.timeoutOutcome,
    required this.operationId,
  });

  final ScenarioLabOperationId operationId;

  @override
  ScenarioScriptStepKind get kind => ScenarioScriptStepKind.operation;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'operationId': operationId.value,
    'timeoutMs': timeoutMs,
    'timeoutOutcome': timeoutOutcome.name,
  };

  factory OperationScenarioScriptStep.fromJson(Object? value) {
    final json = _labObject(value, 'OperationScenarioScriptStep');
    _labOnly(json, const <String>{
      'id',
      'kind',
      'operationId',
      'timeoutMs',
      'timeoutOutcome',
    }, 'OperationScenarioScriptStep');
    if (json['kind'] != ScenarioScriptStepKind.operation.name) {
      throw const FormatException('Invalid operation script step kind');
    }
    return OperationScenarioScriptStep(
      id: _labString(json, 'id', 'OperationScenarioScriptStep'),
      operationId: ScenarioLabOperationId(
        _labString(json, 'operationId', 'OperationScenarioScriptStep'),
      ),
      timeoutMs: _labInteger(json, 'timeoutMs', 'OperationScenarioScriptStep'),
      timeoutOutcome: _labEnum(
        ScenarioScriptTimeoutOutcome.values,
        _labString(json, 'timeoutOutcome', 'OperationScenarioScriptStep'),
        'OperationScenarioScriptStep.timeoutOutcome',
      ),
    );
  }
}

final class ExecutionBindingScenarioScriptStep extends ScenarioScriptStep {
  ExecutionBindingScenarioScriptStep({
    required super.id,
    required super.timeoutMs,
    required super.timeoutOutcome,
    required this.bindingId,
  });

  final ScenarioExecutionBindingId bindingId;

  @override
  ScenarioScriptStepKind get kind => ScenarioScriptStepKind.executionBinding;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'bindingId': bindingId.value,
    'timeoutMs': timeoutMs,
    'timeoutOutcome': timeoutOutcome.name,
  };

  factory ExecutionBindingScenarioScriptStep.fromJson(Object? value) {
    final json = _labObject(value, 'ExecutionBindingScenarioScriptStep');
    _labOnly(json, const <String>{
      'id',
      'kind',
      'bindingId',
      'timeoutMs',
      'timeoutOutcome',
    }, 'ExecutionBindingScenarioScriptStep');
    if (json['kind'] != ScenarioScriptStepKind.executionBinding.name) {
      throw const FormatException('Invalid execution-binding step kind');
    }
    return ExecutionBindingScenarioScriptStep(
      id: _labString(json, 'id', 'ExecutionBindingScenarioScriptStep'),
      bindingId: ScenarioExecutionBindingId(
        _labString(json, 'bindingId', 'ExecutionBindingScenarioScriptStep'),
      ),
      timeoutMs: _labInteger(
        json,
        'timeoutMs',
        'ExecutionBindingScenarioScriptStep',
      ),
      timeoutOutcome: _labEnum(
        ScenarioScriptTimeoutOutcome.values,
        _labString(
          json,
          'timeoutOutcome',
          'ExecutionBindingScenarioScriptStep',
        ),
        'ExecutionBindingScenarioScriptStep.timeoutOutcome',
      ),
    );
  }
}

final class ScenarioScriptDefinition {
  ScenarioScriptDefinition({
    required this.id,
    required this.scenarioId,
    required this.displayName,
    required this.timeoutMs,
    required this.timeoutOutcome,
    required this.cancellationPolicy,
    required Iterable<ScenarioScriptStep> steps,
  }) : steps = List<ScenarioScriptStep>.unmodifiable(steps) {
    _labText(
      displayName,
      'ScenarioScriptDefinition.displayName',
      maxLength: 512,
    );
    if (timeoutMs < 1 || timeoutMs > 1800000) {
      throw ArgumentError.value(
        timeoutMs,
        'timeoutMs',
        'must be between 1 and 1800000',
      );
    }
    if (this.steps.isEmpty ||
        this.steps.length > 1000 ||
        this.steps.map((step) => step.id).toSet().length != this.steps.length ||
        this.steps.any((step) => step.timeoutMs > timeoutMs)) {
      throw ArgumentError('ScenarioScriptDefinition steps are invalid');
    }
    final bindingSteps = this.steps
        .whereType<ExecutionBindingScenarioScriptStep>()
        .toList(growable: false);
    if (bindingSteps.length != 1 ||
        this.steps.first is! ExecutionBindingScenarioScriptStep) {
      throw ArgumentError(
        'Scenario script requires exactly one execution binding as its first step',
      );
    }
  }

  final ScenarioScriptId id;
  final ScenarioId scenarioId;
  final String displayName;
  final int timeoutMs;
  final ScenarioScriptTimeoutOutcome timeoutOutcome;
  final ScenarioScriptCancellationPolicy cancellationPolicy;
  final List<ScenarioScriptStep> steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'displayName': displayName,
    'timeoutMs': timeoutMs,
    'timeoutOutcome': timeoutOutcome.name,
    'cancellationPolicy': cancellationPolicy.name,
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  factory ScenarioScriptDefinition.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioScriptDefinition');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'displayName',
      'timeoutMs',
      'timeoutOutcome',
      'cancellationPolicy',
      'steps',
    }, 'ScenarioScriptDefinition');
    return ScenarioScriptDefinition(
      id: ScenarioScriptId(_labString(json, 'id', 'ScenarioScriptDefinition')),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'ScenarioScriptDefinition'),
      ),
      displayName: _labString(
        json,
        'displayName',
        'ScenarioScriptDefinition',
        maxLength: 512,
      ),
      timeoutMs: _labInteger(json, 'timeoutMs', 'ScenarioScriptDefinition'),
      timeoutOutcome: _labEnum(
        ScenarioScriptTimeoutOutcome.values,
        _labString(json, 'timeoutOutcome', 'ScenarioScriptDefinition'),
        'ScenarioScriptDefinition.timeoutOutcome',
      ),
      cancellationPolicy: _labEnum(
        ScenarioScriptCancellationPolicy.values,
        _labString(json, 'cancellationPolicy', 'ScenarioScriptDefinition'),
        'ScenarioScriptDefinition.cancellationPolicy',
      ),
      steps: _labList(
        json,
        'steps',
        'ScenarioScriptDefinition',
        minItems: 1,
        maxItems: 1000,
      ).map(ScenarioScriptStep.fromJson),
    );
  }
}

sealed class AutomatedAcceptanceCriterion {
  AutomatedAcceptanceCriterion({
    required this.id,
    required this.scenarioId,
    required this.displayName,
  }) {
    _labText(
      displayName,
      'AutomatedAcceptanceCriterion.displayName',
      maxLength: 512,
    );
  }

  final AutomatedAcceptanceCriterionId id;
  final ScenarioId scenarioId;
  final String displayName;

  AutomatedAcceptanceCriterionKind get kind;

  Map<String, Object?> toJson();

  factory AutomatedAcceptanceCriterion.fromJson(Object? value) {
    final json = _labObject(value, 'AutomatedAcceptanceCriterion');
    final kind = _labEnum(
      AutomatedAcceptanceCriterionKind.values,
      _labString(json, 'kind', 'AutomatedAcceptanceCriterion'),
      'AutomatedAcceptanceCriterion.kind',
    );
    return switch (kind) {
      AutomatedAcceptanceCriterionKind.scriptSucceeded =>
        ScriptSucceededAcceptanceCriterion.fromJson(json),
      AutomatedAcceptanceCriterionKind.evidenceAccepted =>
        EvidenceAcceptedAcceptanceCriterion.fromJson(json),
      AutomatedAcceptanceCriterionKind.controlEquals =>
        ControlEqualsAcceptanceCriterion.fromJson(json),
    };
  }
}

final class ScriptSucceededAcceptanceCriterion
    extends AutomatedAcceptanceCriterion {
  ScriptSucceededAcceptanceCriterion({
    required super.id,
    required super.scenarioId,
    required super.displayName,
    required this.scriptId,
  });

  final ScenarioScriptId scriptId;

  @override
  AutomatedAcceptanceCriterionKind get kind =>
      AutomatedAcceptanceCriterionKind.scriptSucceeded;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'displayName': displayName,
    'kind': kind.name,
    'scriptId': scriptId.value,
  };

  factory ScriptSucceededAcceptanceCriterion.fromJson(Object? value) {
    final json = _labObject(value, 'ScriptSucceededAcceptanceCriterion');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'displayName',
      'kind',
      'scriptId',
    }, 'ScriptSucceededAcceptanceCriterion');
    if (json['kind'] != AutomatedAcceptanceCriterionKind.scriptSucceeded.name) {
      throw const FormatException('Invalid script acceptance criterion kind');
    }
    return ScriptSucceededAcceptanceCriterion(
      id: AutomatedAcceptanceCriterionId(
        _labString(json, 'id', 'ScriptSucceededAcceptanceCriterion'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'ScriptSucceededAcceptanceCriterion'),
      ),
      displayName: _labString(
        json,
        'displayName',
        'ScriptSucceededAcceptanceCriterion',
        maxLength: 512,
      ),
      scriptId: ScenarioScriptId(
        _labString(json, 'scriptId', 'ScriptSucceededAcceptanceCriterion'),
      ),
    );
  }
}

final class EvidenceAcceptedAcceptanceCriterion
    extends AutomatedAcceptanceCriterion {
  EvidenceAcceptedAcceptanceCriterion({
    required super.id,
    required super.scenarioId,
    required super.displayName,
    required this.evidenceRequirementId,
  });

  final RequiredEvidenceId evidenceRequirementId;

  @override
  AutomatedAcceptanceCriterionKind get kind =>
      AutomatedAcceptanceCriterionKind.evidenceAccepted;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'displayName': displayName,
    'kind': kind.name,
    'evidenceRequirementId': evidenceRequirementId.value,
  };

  factory EvidenceAcceptedAcceptanceCriterion.fromJson(Object? value) {
    final json = _labObject(value, 'EvidenceAcceptedAcceptanceCriterion');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'displayName',
      'kind',
      'evidenceRequirementId',
    }, 'EvidenceAcceptedAcceptanceCriterion');
    if (json['kind'] !=
        AutomatedAcceptanceCriterionKind.evidenceAccepted.name) {
      throw const FormatException('Invalid evidence acceptance criterion kind');
    }
    return EvidenceAcceptedAcceptanceCriterion(
      id: AutomatedAcceptanceCriterionId(
        _labString(json, 'id', 'EvidenceAcceptedAcceptanceCriterion'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'EvidenceAcceptedAcceptanceCriterion'),
      ),
      displayName: _labString(
        json,
        'displayName',
        'EvidenceAcceptedAcceptanceCriterion',
        maxLength: 512,
      ),
      evidenceRequirementId: RequiredEvidenceId(
        _labString(
          json,
          'evidenceRequirementId',
          'EvidenceAcceptedAcceptanceCriterion',
        ),
      ),
    );
  }
}

final class ControlEqualsAcceptanceCriterion
    extends AutomatedAcceptanceCriterion {
  ControlEqualsAcceptanceCriterion({
    required super.id,
    required super.scenarioId,
    required super.displayName,
    required this.controlId,
    required this.expectedValue,
  });

  final ScenarioControlId controlId;
  final ScenarioControlValue expectedValue;

  @override
  AutomatedAcceptanceCriterionKind get kind =>
      AutomatedAcceptanceCriterionKind.controlEquals;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'displayName': displayName,
    'kind': kind.name,
    'controlId': controlId.value,
    'expectedValue': expectedValue.toJson(),
  };

  factory ControlEqualsAcceptanceCriterion.fromJson(Object? value) {
    final json = _labObject(value, 'ControlEqualsAcceptanceCriterion');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'displayName',
      'kind',
      'controlId',
      'expectedValue',
    }, 'ControlEqualsAcceptanceCriterion');
    if (json['kind'] != AutomatedAcceptanceCriterionKind.controlEquals.name) {
      throw const FormatException('Invalid control acceptance criterion kind');
    }
    return ControlEqualsAcceptanceCriterion(
      id: AutomatedAcceptanceCriterionId(
        _labString(json, 'id', 'ControlEqualsAcceptanceCriterion'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'ControlEqualsAcceptanceCriterion'),
      ),
      displayName: _labString(
        json,
        'displayName',
        'ControlEqualsAcceptanceCriterion',
        maxLength: 512,
      ),
      controlId: ScenarioControlId(
        _labString(json, 'controlId', 'ControlEqualsAcceptanceCriterion'),
      ),
      expectedValue: ScenarioControlValue.fromJson(json['expectedValue']),
    );
  }
}

final class HumanApprovalRequirement {
  HumanApprovalRequirement({
    required this.id,
    required this.scenarioId,
    required this.reviewGuideId,
    required this.reviewGuideStepId,
    required this.scope,
  }) {
    _labId(reviewGuideStepId, 'ReviewGuideStep');
  }

  final HumanApprovalRequirementId id;
  final ScenarioId scenarioId;
  final ReviewGuideId reviewGuideId;
  final String reviewGuideStepId;
  final HumanApprovalScope scope;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'reviewGuideId': reviewGuideId.value,
    'reviewGuideStepId': reviewGuideStepId,
    'scope': scope.name,
  };

  factory HumanApprovalRequirement.fromJson(Object? value) {
    final json = _labObject(value, 'HumanApprovalRequirement');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'reviewGuideId',
      'reviewGuideStepId',
      'scope',
    }, 'HumanApprovalRequirement');
    return HumanApprovalRequirement(
      id: HumanApprovalRequirementId(
        _labString(json, 'id', 'HumanApprovalRequirement'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'HumanApprovalRequirement'),
      ),
      reviewGuideId: ReviewGuideId(
        _labString(json, 'reviewGuideId', 'HumanApprovalRequirement'),
      ),
      reviewGuideStepId: _labString(
        json,
        'reviewGuideStepId',
        'HumanApprovalRequirement',
      ),
      scope: _labEnum(
        HumanApprovalScope.values,
        _labString(json, 'scope', 'HumanApprovalRequirement'),
        'HumanApprovalRequirement.scope',
      ),
    );
  }
}

sealed class ComparisonInputReference {
  const ComparisonInputReference();

  ComparisonInputKind get kind;

  Map<String, Object?> toJson();

  factory ComparisonInputReference.fromJson(Object? value) {
    final json = _labObject(value, 'ComparisonInputReference');
    final kind = _labEnum(
      ComparisonInputKind.values,
      _labString(json, 'kind', 'ComparisonInputReference'),
      'ComparisonInputReference.kind',
    );
    return switch (kind) {
      ComparisonInputKind.artifact => ArtifactComparisonInputReference.fromJson(
        json,
      ),
      ComparisonInputKind.evidence => EvidenceComparisonInputReference.fromJson(
        json,
      ),
      ComparisonInputKind.requiredEvidence =>
        RequiredEvidenceComparisonInputReference.fromJson(json),
    };
  }
}

final class ArtifactComparisonInputReference extends ComparisonInputReference {
  const ArtifactComparisonInputReference({required this.artifactId});

  final SupplementalArtifactId artifactId;

  @override
  ComparisonInputKind get kind => ComparisonInputKind.artifact;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'artifactId': artifactId.value,
  };

  factory ArtifactComparisonInputReference.fromJson(Object? value) {
    final json = _labObject(value, 'ArtifactComparisonInputReference');
    _labOnly(json, const <String>{
      'kind',
      'artifactId',
    }, 'ArtifactComparisonInputReference');
    if (json['kind'] != ComparisonInputKind.artifact.name) {
      throw const FormatException('Invalid artifact comparison input kind');
    }
    return ArtifactComparisonInputReference(
      artifactId: SupplementalArtifactId(
        _labString(json, 'artifactId', 'ArtifactComparisonInputReference'),
      ),
    );
  }
}

final class EvidenceComparisonInputReference extends ComparisonInputReference {
  const EvidenceComparisonInputReference({
    required this.evidenceDigest,
    required this.provenanceDigest,
    required this.classification,
  });

  final Digest evidenceDigest;
  final Digest provenanceDigest;
  final ArtifactClassification classification;

  @override
  ComparisonInputKind get kind => ComparisonInputKind.evidence;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'evidenceDigest': evidenceDigest.value,
    'provenanceDigest': provenanceDigest.value,
    'classification': classification.name,
  };

  factory EvidenceComparisonInputReference.fromJson(Object? value) {
    final json = _labObject(value, 'EvidenceComparisonInputReference');
    _labOnly(json, const <String>{
      'kind',
      'evidenceDigest',
      'provenanceDigest',
      'classification',
    }, 'EvidenceComparisonInputReference');
    if (json['kind'] != ComparisonInputKind.evidence.name) {
      throw const FormatException('Invalid Evidence comparison input kind');
    }
    return EvidenceComparisonInputReference(
      evidenceDigest: Digest(
        _labString(json, 'evidenceDigest', 'EvidenceComparisonInputReference'),
      ),
      provenanceDigest: Digest(
        _labString(
          json,
          'provenanceDigest',
          'EvidenceComparisonInputReference',
        ),
      ),
      classification: _labEnum(
        ArtifactClassification.values,
        _labString(json, 'classification', 'EvidenceComparisonInputReference'),
        'EvidenceComparisonInputReference.classification',
      ),
    );
  }
}

final class RequiredEvidenceComparisonInputReference
    extends ComparisonInputReference {
  /// References a collected RequiredEvidence result.
  ///
  /// When [requiredEvidenceId] equals the binding's own requirement, this is
  /// the current collection and is valid only as candidate. Runtime comparison
  /// must fail explicitly unless that collection contains exactly one artifact.
  const RequiredEvidenceComparisonInputReference({
    required this.requiredEvidenceId,
  });

  final RequiredEvidenceId requiredEvidenceId;

  @override
  ComparisonInputKind get kind => ComparisonInputKind.requiredEvidence;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'requiredEvidenceId': requiredEvidenceId.value,
  };

  factory RequiredEvidenceComparisonInputReference.fromJson(Object? value) {
    final json = _labObject(value, 'RequiredEvidenceComparisonInputReference');
    _labOnly(json, const <String>{
      'kind',
      'requiredEvidenceId',
    }, 'RequiredEvidenceComparisonInputReference');
    if (json['kind'] != ComparisonInputKind.requiredEvidence.name) {
      throw const FormatException(
        'Invalid required-Evidence comparison input kind',
      );
    }
    return RequiredEvidenceComparisonInputReference(
      requiredEvidenceId: RequiredEvidenceId(
        _labString(
          json,
          'requiredEvidenceId',
          'RequiredEvidenceComparisonInputReference',
        ),
      ),
    );
  }
}

final class SupplementalArtifactReference {
  const SupplementalArtifactReference({
    required this.id,
    required this.scenarioId,
    required this.requiredEvidenceId,
    required this.role,
    required this.artifactDigest,
    required this.provenanceDigest,
    required this.classification,
  });

  final SupplementalArtifactId id;
  final ScenarioId scenarioId;
  final RequiredEvidenceId requiredEvidenceId;
  final SupplementalArtifactRole role;
  final Digest artifactDigest;
  final Digest provenanceDigest;
  final ArtifactClassification classification;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'requiredEvidenceId': requiredEvidenceId.value,
    'role': role.name,
    'artifactDigest': artifactDigest.value,
    'provenanceDigest': provenanceDigest.value,
    'classification': classification.name,
  };

  factory SupplementalArtifactReference.fromJson(Object? value) {
    final json = _labObject(value, 'SupplementalArtifactReference');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'requiredEvidenceId',
      'role',
      'artifactDigest',
      'provenanceDigest',
      'classification',
    }, 'SupplementalArtifactReference');
    return SupplementalArtifactReference(
      id: SupplementalArtifactId(
        _labString(json, 'id', 'SupplementalArtifactReference'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'SupplementalArtifactReference'),
      ),
      requiredEvidenceId: RequiredEvidenceId(
        _labString(json, 'requiredEvidenceId', 'SupplementalArtifactReference'),
      ),
      role: _labEnum(
        SupplementalArtifactRole.values,
        _labString(json, 'role', 'SupplementalArtifactReference'),
        'SupplementalArtifactReference.role',
      ),
      artifactDigest: Digest(
        _labString(json, 'artifactDigest', 'SupplementalArtifactReference'),
      ),
      provenanceDigest: Digest(
        _labString(json, 'provenanceDigest', 'SupplementalArtifactReference'),
      ),
      classification: _labEnum(
        ArtifactClassification.values,
        _labString(json, 'classification', 'SupplementalArtifactReference'),
        'SupplementalArtifactReference.classification',
      ),
    );
  }
}

final class ScenarioComparisonBinding {
  ScenarioComparisonBinding({
    required this.id,
    required this.scenarioId,
    required this.requiredEvidenceId,
    required this.baseline,
    required this.candidate,
  }) {
    if (Digest.semantic(baseline.toJson()) ==
        Digest.semantic(candidate.toJson())) {
      throw ArgumentError('Comparison baseline and candidate must differ');
    }
  }

  final ScenarioComparisonBindingId id;
  final ScenarioId scenarioId;
  final RequiredEvidenceId requiredEvidenceId;
  final ComparisonInputReference baseline;
  final ComparisonInputReference candidate;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'requiredEvidenceId': requiredEvidenceId.value,
    'baseline': baseline.toJson(),
    'candidate': candidate.toJson(),
  };

  factory ScenarioComparisonBinding.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioComparisonBinding');
    _labOnly(json, const <String>{
      'id',
      'scenarioId',
      'requiredEvidenceId',
      'baseline',
      'candidate',
    }, 'ScenarioComparisonBinding');
    return ScenarioComparisonBinding(
      id: ScenarioComparisonBindingId(
        _labString(json, 'id', 'ScenarioComparisonBinding'),
      ),
      scenarioId: ScenarioId(
        _labString(json, 'scenarioId', 'ScenarioComparisonBinding'),
      ),
      requiredEvidenceId: RequiredEvidenceId(
        _labString(json, 'requiredEvidenceId', 'ScenarioComparisonBinding'),
      ),
      baseline: ComparisonInputReference.fromJson(json['baseline']),
      candidate: ComparisonInputReference.fromJson(json['candidate']),
    );
  }
}

final class ScenarioLabPlan {
  ScenarioLabPlan({
    required this.scenarioId,
    required Iterable<ScenarioExecutionBindingId> executionBindingIds,
    required Iterable<ScenarioControlId> controlIds,
    required Iterable<ScenarioLabOperationId> operationIds,
    required Iterable<ScenarioScriptId> scriptIds,
    required Iterable<AutomatedAcceptanceCriterionId>
    automatedAcceptanceCriterionIds,
    required Iterable<RequiredEvidenceId> requiredEvidenceIds,
    required Iterable<ScenarioComparisonBindingId> comparisonBindingIds,
    required Iterable<HumanApprovalRequirementId> humanApprovalRequirementIds,
    required Iterable<SupplementalArtifactId> supplementalArtifactIds,
  }) : executionBindingIds = _labSortedIds(
         executionBindingIds,
         'ScenarioLabPlan.executionBindingIds',
         minItems: 1,
         maxItems: 256,
       ),
       controlIds = _labSortedIds(
         controlIds,
         'ScenarioLabPlan.controlIds',
         minItems: 0,
         maxItems: 256,
       ),
       operationIds = _labSortedIds(
         operationIds,
         'ScenarioLabPlan.operationIds',
         minItems: 0,
         maxItems: 10000,
       ),
       scriptIds = _labSortedIds(
         scriptIds,
         'ScenarioLabPlan.scriptIds',
         minItems: 1,
         maxItems: 1000,
       ),
       automatedAcceptanceCriterionIds = _labSortedIds(
         automatedAcceptanceCriterionIds,
         'ScenarioLabPlan.automatedAcceptanceCriterionIds',
         minItems: 0,
         maxItems: 10000,
       ),
       requiredEvidenceIds = _labSortedIds(
         requiredEvidenceIds,
         'ScenarioLabPlan.requiredEvidenceIds',
         minItems: 0,
         maxItems: 1000,
       ),
       comparisonBindingIds = _labSortedIds(
         comparisonBindingIds,
         'ScenarioLabPlan.comparisonBindingIds',
         minItems: 0,
         maxItems: 1000,
       ),
       humanApprovalRequirementIds = _labSortedIds(
         humanApprovalRequirementIds,
         'ScenarioLabPlan.humanApprovalRequirementIds',
         minItems: 0,
         maxItems: 1000,
       ),
       supplementalArtifactIds = _labSortedIds(
         supplementalArtifactIds,
         'ScenarioLabPlan.supplementalArtifactIds',
         minItems: 0,
         maxItems: 1000,
       );

  final ScenarioId scenarioId;
  final List<ScenarioExecutionBindingId> executionBindingIds;
  final List<ScenarioControlId> controlIds;
  final List<ScenarioLabOperationId> operationIds;
  final List<ScenarioScriptId> scriptIds;
  final List<AutomatedAcceptanceCriterionId> automatedAcceptanceCriterionIds;
  final List<RequiredEvidenceId> requiredEvidenceIds;
  final List<ScenarioComparisonBindingId> comparisonBindingIds;
  final List<HumanApprovalRequirementId> humanApprovalRequirementIds;
  final List<SupplementalArtifactId> supplementalArtifactIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'scenarioId': scenarioId.value,
    'executionBindingIds': executionBindingIds.map((id) => id.value).toList(),
    'controlIds': controlIds.map((id) => id.value).toList(),
    'operationIds': operationIds.map((id) => id.value).toList(),
    'scriptIds': scriptIds.map((id) => id.value).toList(),
    'automatedAcceptanceCriterionIds': automatedAcceptanceCriterionIds
        .map((id) => id.value)
        .toList(),
    'requiredEvidenceIds': requiredEvidenceIds.map((id) => id.value).toList(),
    'comparisonBindingIds': comparisonBindingIds.map((id) => id.value).toList(),
    'humanApprovalRequirementIds': humanApprovalRequirementIds
        .map((id) => id.value)
        .toList(),
    'supplementalArtifactIds': supplementalArtifactIds
        .map((id) => id.value)
        .toList(),
  };

  factory ScenarioLabPlan.fromJson(Object? value) {
    final json = _labObject(value, 'ScenarioLabPlan');
    _labOnly(json, const <String>{
      'scenarioId',
      'executionBindingIds',
      'controlIds',
      'operationIds',
      'scriptIds',
      'automatedAcceptanceCriterionIds',
      'requiredEvidenceIds',
      'comparisonBindingIds',
      'humanApprovalRequirementIds',
      'supplementalArtifactIds',
    }, 'ScenarioLabPlan');
    return ScenarioLabPlan(
      scenarioId: ScenarioId(_labString(json, 'scenarioId', 'ScenarioLabPlan')),
      executionBindingIds: _labStringList(
        json,
        'executionBindingIds',
        'ScenarioLabPlan',
        minItems: 1,
        maxItems: 256,
      ).map(ScenarioExecutionBindingId.new),
      controlIds: _labStringList(
        json,
        'controlIds',
        'ScenarioLabPlan',
        minItems: 0,
        maxItems: 256,
      ).map(ScenarioControlId.new),
      operationIds: _labStringList(
        json,
        'operationIds',
        'ScenarioLabPlan',
        minItems: 0,
        maxItems: 10000,
      ).map(ScenarioLabOperationId.new),
      scriptIds: _labStringList(
        json,
        'scriptIds',
        'ScenarioLabPlan',
        minItems: 1,
        maxItems: 1000,
      ).map(ScenarioScriptId.new),
      automatedAcceptanceCriterionIds: _labStringList(
        json,
        'automatedAcceptanceCriterionIds',
        'ScenarioLabPlan',
        minItems: 0,
        maxItems: 10000,
      ).map(AutomatedAcceptanceCriterionId.new),
      requiredEvidenceIds: _labStringList(
        json,
        'requiredEvidenceIds',
        'ScenarioLabPlan',
        minItems: 0,
        maxItems: 1000,
      ).map(RequiredEvidenceId.new),
      comparisonBindingIds: _labStringList(
        json,
        'comparisonBindingIds',
        'ScenarioLabPlan',
        minItems: 0,
        maxItems: 1000,
      ).map(ScenarioComparisonBindingId.new),
      humanApprovalRequirementIds: _labStringList(
        json,
        'humanApprovalRequirementIds',
        'ScenarioLabPlan',
        minItems: 0,
        maxItems: 1000,
      ).map(HumanApprovalRequirementId.new),
      supplementalArtifactIds: _labStringList(
        json,
        'supplementalArtifactIds',
        'ScenarioLabPlan',
        minItems: 0,
        maxItems: 1000,
      ).map(SupplementalArtifactId.new),
    );
  }
}

/// Catalog-bound, declarative inputs for Scenario Lab and Quality.
///
/// It deliberately contains no routing, URLs, commands, dynamic argument maps
/// or executable callbacks. Scripts can only select catalog bindings or
/// operations declared and allowlisted by this manifest.
final class ScenarioLabManifest {
  ScenarioLabManifest({
    required CatalogManifest catalog,
    required Iterable<CapabilityDescriptor> appAdapterCapabilities,
    required Iterable<ScenarioControlDefinition> controls,
    required Iterable<ScenarioLabOperationDefinition> operations,
    required Iterable<ScenarioScriptDefinition> scripts,
    required Iterable<AutomatedAcceptanceCriterion> automatedAcceptanceCriteria,
    required Iterable<RequiredEvidenceDefinition> requiredEvidence,
    required Iterable<ScenarioComparisonBinding> comparisonBindings,
    required Iterable<VisualComparisonPolicy> visualComparisonPolicies,
    required Iterable<SemanticComparisonPolicy> semanticComparisonPolicies,
    required Iterable<HumanApprovalRequirement> humanApprovalRequirements,
    required Iterable<SupplementalArtifactReference> supplementalArtifacts,
    required Iterable<ScenarioLabPlan> plans,
  }) : catalogDigest = catalog.digest,
       appAdapterCapabilities = _labSorted(
         appAdapterCapabilities,
         (item) => '${item.id}@${item.version}',
         'ScenarioLabManifest.appAdapterCapabilities',
         maxItems: 10000,
       ),
       controls = _labSorted(
         controls,
         (item) => item.id.value,
         'ScenarioLabManifest.controls',
         maxItems: 100000,
       ),
       operations = _labSorted(
         operations,
         (item) => item.id.value,
         'ScenarioLabManifest.operations',
         maxItems: 100000,
       ),
       scripts = _labSorted(
         scripts,
         (item) => item.id.value,
         'ScenarioLabManifest.scripts',
         maxItems: 100000,
       ),
       automatedAcceptanceCriteria = _labSorted(
         automatedAcceptanceCriteria,
         (item) => item.id.value,
         'ScenarioLabManifest.automatedAcceptanceCriteria',
         maxItems: 100000,
       ),
       requiredEvidence = _labSorted(
         requiredEvidence,
         (item) => item.id.value,
         'ScenarioLabManifest.requiredEvidence',
         maxItems: 100000,
       ),
       comparisonBindings = _labSorted(
         comparisonBindings,
         (item) => item.id.value,
         'ScenarioLabManifest.comparisonBindings',
         maxItems: 100000,
       ),
       visualComparisonPolicies = _labSorted(
         visualComparisonPolicies,
         (item) => item.id,
         'ScenarioLabManifest.visualComparisonPolicies',
         maxItems: 10000,
       ),
       semanticComparisonPolicies = _labSorted(
         semanticComparisonPolicies,
         (item) => item.id,
         'ScenarioLabManifest.semanticComparisonPolicies',
         maxItems: 10000,
       ),
       humanApprovalRequirements = _labSorted(
         humanApprovalRequirements,
         (item) => item.id.value,
         'ScenarioLabManifest.humanApprovalRequirements',
         maxItems: 100000,
       ),
       supplementalArtifacts = _labSorted(
         supplementalArtifacts,
         (item) => item.id.value,
         'ScenarioLabManifest.supplementalArtifacts',
         maxItems: 100000,
       ),
       plans = _labSorted(
         plans,
         (item) => item.scenarioId.value,
         'ScenarioLabManifest.plans',
         maxItems: 100000,
       ) {
    _validateScenarioLabManifest(this, catalog);
  }

  static const int schemaVersion = 1;

  final Digest catalogDigest;
  final List<CapabilityDescriptor> appAdapterCapabilities;
  final List<ScenarioControlDefinition> controls;
  final List<ScenarioLabOperationDefinition> operations;
  final List<ScenarioScriptDefinition> scripts;
  final List<AutomatedAcceptanceCriterion> automatedAcceptanceCriteria;
  final List<RequiredEvidenceDefinition> requiredEvidence;
  final List<ScenarioComparisonBinding> comparisonBindings;
  final List<VisualComparisonPolicy> visualComparisonPolicies;
  final List<SemanticComparisonPolicy> semanticComparisonPolicies;
  final List<HumanApprovalRequirement> humanApprovalRequirements;
  final List<SupplementalArtifactReference> supplementalArtifacts;
  final List<ScenarioLabPlan> plans;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabManifest',
    'catalogDigest': catalogDigest.value,
    'appAdapterCapabilities': appAdapterCapabilities
        .map((item) => item.toJson())
        .toList(),
    'controls': controls.map((item) => item.toJson()).toList(),
    'operations': operations.map((item) => item.toJson()).toList(),
    'scripts': scripts.map((item) => item.toJson()).toList(),
    'automatedAcceptanceCriteria': automatedAcceptanceCriteria
        .map((item) => item.toJson())
        .toList(),
    'requiredEvidence': requiredEvidence.map((item) => item.toJson()).toList(),
    'comparisonBindings': comparisonBindings
        .map((item) => item.toJson())
        .toList(),
    'visualComparisonPolicies': visualComparisonPolicies
        .map((item) => item.toJson())
        .toList(),
    'semanticComparisonPolicies': semanticComparisonPolicies
        .map((item) => item.toJson())
        .toList(),
    'humanApprovalRequirements': humanApprovalRequirements
        .map((item) => item.toJson())
        .toList(),
    'supplementalArtifacts': supplementalArtifacts
        .map((item) => item.toJson())
        .toList(),
    'plans': plans.map((item) => item.toJson()).toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabManifest.fromJson(
    Object? value, {
    required CatalogManifest catalog,
  }) {
    final json = _labObject(value, 'ScenarioLabManifest');
    _labOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'catalogDigest',
      'appAdapterCapabilities',
      'controls',
      'operations',
      'scripts',
      'automatedAcceptanceCriteria',
      'requiredEvidence',
      'comparisonBindings',
      'visualComparisonPolicies',
      'semanticComparisonPolicies',
      'humanApprovalRequirements',
      'supplementalArtifacts',
      'plans',
      'digest',
    }, 'ScenarioLabManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ScenarioLabManifest') {
      throw const FormatException(
        'ScenarioLabManifest has invalid schemaVersion or kind',
      );
    }
    final advertisedCatalogDigest = Digest(
      _labString(json, 'catalogDigest', 'ScenarioLabManifest'),
    );
    if (advertisedCatalogDigest != catalog.digest) {
      throw const FormatException('ScenarioLabManifest catalogDigest mismatch');
    }
    final manifest = ScenarioLabManifest(
      catalog: catalog,
      appAdapterCapabilities: _labList(
        json,
        'appAdapterCapabilities',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 10000,
      ).map(CapabilityDescriptor.fromJson),
      controls: _labList(
        json,
        'controls',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 100000,
      ).map(ScenarioControlDefinition.fromJson),
      operations: _labList(
        json,
        'operations',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 100000,
      ).map(ScenarioLabOperationDefinition.fromJson),
      scripts: _labList(
        json,
        'scripts',
        'ScenarioLabManifest',
        minItems: 1,
        maxItems: 100000,
      ).map(ScenarioScriptDefinition.fromJson),
      automatedAcceptanceCriteria: _labList(
        json,
        'automatedAcceptanceCriteria',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 100000,
      ).map(AutomatedAcceptanceCriterion.fromJson),
      requiredEvidence: _labList(
        json,
        'requiredEvidence',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 100000,
      ).map(RequiredEvidenceDefinition.fromJson),
      comparisonBindings: _labList(
        json,
        'comparisonBindings',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 100000,
      ).map(ScenarioComparisonBinding.fromJson),
      visualComparisonPolicies: _labList(
        json,
        'visualComparisonPolicies',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 10000,
      ).map(VisualComparisonPolicy.fromJson),
      semanticComparisonPolicies: _labList(
        json,
        'semanticComparisonPolicies',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 10000,
      ).map(SemanticComparisonPolicy.fromJson),
      humanApprovalRequirements: _labList(
        json,
        'humanApprovalRequirements',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 100000,
      ).map(HumanApprovalRequirement.fromJson),
      supplementalArtifacts: _labList(
        json,
        'supplementalArtifacts',
        'ScenarioLabManifest',
        minItems: 0,
        maxItems: 100000,
      ).map(SupplementalArtifactReference.fromJson),
      plans: _labList(
        json,
        'plans',
        'ScenarioLabManifest',
        minItems: 1,
        maxItems: 100000,
      ).map(ScenarioLabPlan.fromJson),
    );
    final advertisedDigest = Digest(
      _labString(json, 'digest', 'ScenarioLabManifest'),
    );
    if (advertisedDigest != manifest.digest) {
      throw const FormatException('ScenarioLabManifest digest mismatch');
    }
    return manifest;
  }

  void validateAgainst(CatalogManifest catalog) {
    if (catalog.digest != catalogDigest) {
      throw ArgumentError('ScenarioLabManifest catalogDigest mismatch');
    }
    _validateScenarioLabManifest(this, catalog);
  }
}

void _validateScenarioLabManifest(
  ScenarioLabManifest manifest,
  CatalogManifest catalog,
) {
  if (manifest.catalogDigest != catalog.digest) {
    throw ArgumentError('ScenarioLabManifest catalogDigest mismatch');
  }
  if (manifest.plans.isEmpty || manifest.scripts.isEmpty) {
    throw ArgumentError(
      'ScenarioLabManifest requires plans with executable scripts',
    );
  }

  final scenarios = <ScenarioId, Scenario>{
    for (final item in catalog.scenarios) item.id: item,
  };
  final bindings = <ScenarioExecutionBindingId, ScenarioExecutionBinding>{
    for (final item in catalog.executionBindings) item.id: item,
  };
  final reviewGuides = <ReviewGuideId, ReviewGuide>{
    for (final item in catalog.reviewGuides) item.id: item,
  };
  final capabilities = <String, CapabilityDescriptor>{};
  for (final capability in manifest.appAdapterCapabilities) {
    final id = AppAdapterCapabilityId(capability.id);
    if (capability.version > 1000000 || capability.operations.length > 256) {
      throw ArgumentError('AppAdapter capability ${capability.id} is invalid');
    }
    for (final operation in capability.operations) {
      CapabilityOperationId(operation);
    }
    final key = '${id.value}@${capability.version}';
    if (capabilities.containsKey(key)) {
      throw ArgumentError('Duplicate AppAdapter capability $key');
    }
    capabilities[key] = capability;
  }

  final controls = <ScenarioControlId, ScenarioControlDefinition>{
    for (final item in manifest.controls) item.id: item,
  };
  final operations = <ScenarioLabOperationId, ScenarioLabOperationDefinition>{
    for (final item in manifest.operations) item.id: item,
  };
  final scripts = <ScenarioScriptId, ScenarioScriptDefinition>{
    for (final item in manifest.scripts) item.id: item,
  };
  final criteria =
      <AutomatedAcceptanceCriterionId, AutomatedAcceptanceCriterion>{
        for (final item in manifest.automatedAcceptanceCriteria) item.id: item,
      };
  final evidence = <RequiredEvidenceId, RequiredEvidenceDefinition>{
    for (final item in manifest.requiredEvidence) item.id: item,
  };
  final comparisons = <ScenarioComparisonBindingId, ScenarioComparisonBinding>{
    for (final item in manifest.comparisonBindings) item.id: item,
  };
  final approvals = <HumanApprovalRequirementId, HumanApprovalRequirement>{
    for (final item in manifest.humanApprovalRequirements) item.id: item,
  };
  final supplemental = <SupplementalArtifactId, SupplementalArtifactReference>{
    for (final item in manifest.supplementalArtifacts) item.id: item,
  };
  final plans = <ScenarioId, ScenarioLabPlan>{
    for (final item in manifest.plans) item.scenarioId: item,
  };
  final visualPolicies = <String, VisualComparisonPolicy>{};
  for (final policy in manifest.visualComparisonPolicies) {
    final id = VisualComparisonPolicyId(policy.id);
    visualPolicies[id.value] = policy;
  }
  final semanticPolicies = <String, SemanticComparisonPolicy>{};
  for (final policy in manifest.semanticComparisonPolicies) {
    final id = SemanticComparisonPolicyId(policy.id);
    if (policy.maxChangedNodes > 1000000) {
      throw ArgumentError(
        'SemanticComparisonPolicy ${policy.id} exceeds the node limit',
      );
    }
    semanticPolicies[id.value] = policy;
  }

  for (final plan in manifest.plans) {
    if (!scenarios.containsKey(plan.scenarioId)) {
      throw ArgumentError(
        'ScenarioLabPlan ${plan.scenarioId} references an unknown Scenario',
      );
    }
  }
  for (final control in manifest.controls) {
    final descriptor = capabilities[control.capability.key];
    final operationIds = <String>{
      control.readOperationId.value,
      control.writeOperationId.value,
      if (control.resetOperationId != null) control.resetOperationId!.value,
    };
    if (!scenarios.containsKey(control.scenarioId) ||
        descriptor == null ||
        !descriptor.operations.containsAll(operationIds)) {
      throw ArgumentError(
        'ScenarioControl ${control.id} has an unknown Scenario/capability operation',
      );
    }
  }
  for (final requirement in manifest.requiredEvidence) {
    final policy = requirement.comparisonPolicy;
    final policyExists = switch (policy.kind) {
      ComparisonPolicyKind.visual => visualPolicies.containsKey(
        policy.policyId,
      ),
      ComparisonPolicyKind.semantic => semanticPolicies.containsKey(
        policy.policyId,
      ),
    };
    if (!scenarios.containsKey(requirement.scenarioId) || !policyExists) {
      throw ArgumentError(
        'RequiredEvidence ${requirement.id} has an unknown Scenario/policy',
      );
    }
  }
  for (final artifact in manifest.supplementalArtifacts) {
    final requirement = evidence[artifact.requiredEvidenceId];
    if (!scenarios.containsKey(artifact.scenarioId) ||
        requirement == null ||
        requirement.scenarioId != artifact.scenarioId ||
        !requirement.allowedClassifications.contains(artifact.classification)) {
      throw ArgumentError(
        'SupplementalArtifact ${artifact.id} has an invalid Scenario, Evidence requirement or classification',
      );
    }
  }
  final comparedRequirements = <RequiredEvidenceId>{};
  final referencedArtifacts = <SupplementalArtifactId>[];
  for (final comparison in manifest.comparisonBindings) {
    final requirement = evidence[comparison.requiredEvidenceId];
    if (!scenarios.containsKey(comparison.scenarioId) ||
        requirement == null ||
        requirement.scenarioId != comparison.scenarioId ||
        !comparedRequirements.add(comparison.requiredEvidenceId)) {
      throw ArgumentError(
        'ScenarioComparisonBinding ${comparison.id} has an invalid or duplicate Evidence requirement',
      );
    }
    _validateComparisonInput(
      comparison.baseline,
      isBaseline: true,
      comparison: comparison,
      requirement: requirement,
      evidence: evidence,
      supplemental: supplemental,
      referencedArtifacts: referencedArtifacts,
    );
    _validateComparisonInput(
      comparison.candidate,
      isBaseline: false,
      comparison: comparison,
      requirement: requirement,
      evidence: evidence,
      supplemental: supplemental,
      referencedArtifacts: referencedArtifacts,
    );
  }
  if (!_sameSet(comparedRequirements, evidence.keys.toSet())) {
    throw ArgumentError(
      'Every required Evidence entry needs exactly one comparison binding',
    );
  }
  _validateRequiredEvidenceGraph(manifest.comparisonBindings);
  if (referencedArtifacts.toSet().length != referencedArtifacts.length) {
    throw ArgumentError(
      'A supplemental comparison artifact may be bound only once',
    );
  }
  final referencedArtifactIds = referencedArtifacts.toSet();
  for (final artifact in manifest.supplementalArtifacts) {
    final isComparisonInput =
        artifact.role != SupplementalArtifactRole.diagnostic;
    if (isComparisonInput != referencedArtifactIds.contains(artifact.id)) {
      throw ArgumentError(
        'SupplementalArtifact ${artifact.id} role/reference mismatch',
      );
    }
  }
  for (final operation in manifest.operations) {
    if (!scenarios.containsKey(operation.scenarioId)) {
      throw ArgumentError(
        'ScenarioLabOperation ${operation.id} references an unknown Scenario',
      );
    }
    switch (operation) {
      case AssignControlOperationDefinition():
        final control = controls[operation.controlId];
        if (control == null ||
            control.scenarioId != operation.scenarioId ||
            !control.domain.accepts(operation.value)) {
          throw ArgumentError(
            'AssignControl operation ${operation.id} is outside its control domain',
          );
        }
      case ResetControlOperationDefinition():
        final control = controls[operation.controlId];
        if (control == null ||
            control.scenarioId != operation.scenarioId ||
            control.resetOperationId == null) {
          throw ArgumentError(
            'ResetControl operation ${operation.id} has no declared reset operation',
          );
        }
      case CollectEvidenceOperationDefinition():
        final requirement = evidence[operation.evidenceRequirementId];
        if (requirement == null ||
            requirement.scenarioId != operation.scenarioId) {
          throw ArgumentError(
            'CollectEvidence operation ${operation.id} has an invalid requirement',
          );
        }
    }
  }
  for (final script in manifest.scripts) {
    if (!scenarios.containsKey(script.scenarioId)) {
      throw ArgumentError(
        'ScenarioScript ${script.id} references an unknown Scenario',
      );
    }
    for (final step in script.steps) {
      switch (step) {
        case OperationScenarioScriptStep():
          final operation = operations[step.operationId];
          if (operation == null || operation.scenarioId != script.scenarioId) {
            throw ArgumentError(
              'ScenarioScript ${script.id} has an invalid operation step',
            );
          }
        case ExecutionBindingScenarioScriptStep():
          final binding = bindings[step.bindingId];
          if (binding == null || binding.scenarioId != script.scenarioId) {
            throw ArgumentError(
              'ScenarioScript ${script.id} has an invalid execution binding step',
            );
          }
      }
    }
  }
  for (final criterion in manifest.automatedAcceptanceCriteria) {
    if (!scenarios.containsKey(criterion.scenarioId)) {
      throw ArgumentError(
        'AutomatedAcceptanceCriterion ${criterion.id} has an unknown Scenario',
      );
    }
    switch (criterion) {
      case ScriptSucceededAcceptanceCriterion():
        final script = scripts[criterion.scriptId];
        if (script == null || script.scenarioId != criterion.scenarioId) {
          throw ArgumentError(
            'Script acceptance criterion ${criterion.id} is invalid',
          );
        }
      case EvidenceAcceptedAcceptanceCriterion():
        final requirement = evidence[criterion.evidenceRequirementId];
        if (requirement == null ||
            requirement.scenarioId != criterion.scenarioId) {
          throw ArgumentError(
            'Evidence acceptance criterion ${criterion.id} is invalid',
          );
        }
      case ControlEqualsAcceptanceCriterion():
        final control = controls[criterion.controlId];
        if (control == null ||
            control.scenarioId != criterion.scenarioId ||
            !control.domain.accepts(criterion.expectedValue)) {
          throw ArgumentError(
            'Control acceptance criterion ${criterion.id} is invalid',
          );
        }
    }
  }
  for (final approval in manifest.humanApprovalRequirements) {
    final guide = reviewGuides[approval.reviewGuideId];
    final step = guide?.steps
        .where((item) => item.id == approval.reviewGuideStepId)
        .firstOrNull;
    final plan = plans[approval.scenarioId];
    if (guide == null ||
        step == null ||
        plan == null ||
        step.scenarioId != approval.scenarioId ||
        !plan.executionBindingIds.contains(step.bindingId)) {
      throw ArgumentError(
        'HumanApprovalRequirement ${approval.id} has an invalid ReviewGuide step',
      );
    }
  }

  final acceptedEvidence = manifest.automatedAcceptanceCriteria
      .whereType<EvidenceAcceptedAcceptanceCriterion>()
      .map((item) => item.evidenceRequirementId)
      .toSet();
  final collectedEvidence = manifest.operations
      .whereType<CollectEvidenceOperationDefinition>()
      .map((item) => item.evidenceRequirementId)
      .toSet();
  if (evidence.keys.any(
    (id) => !acceptedEvidence.contains(id) || !collectedEvidence.contains(id),
  )) {
    throw ArgumentError(
      'Every Evidence requirement needs collection and automated acceptance',
    );
  }

  final usedCapabilities = manifest.controls
      .map((control) => control.capability.key)
      .toSet();
  if (capabilities.keys.any((key) => !usedCapabilities.contains(key))) {
    throw ArgumentError('ScenarioLabManifest contains an unused capability');
  }
  final usedVisualPolicies = manifest.requiredEvidence
      .map((item) => item.comparisonPolicy)
      .where((item) => item.kind == ComparisonPolicyKind.visual)
      .map((item) => item.policyId)
      .toSet();
  final usedSemanticPolicies = manifest.requiredEvidence
      .map((item) => item.comparisonPolicy)
      .where((item) => item.kind == ComparisonPolicyKind.semantic)
      .map((item) => item.policyId)
      .toSet();
  if (visualPolicies.keys.any((id) => !usedVisualPolicies.contains(id)) ||
      semanticPolicies.keys.any((id) => !usedSemanticPolicies.contains(id))) {
    throw ArgumentError('ScenarioLabManifest contains an unused policy');
  }

  _validatePlanMembership(
    manifest.plans.expand((plan) => plan.controlIds),
    controls.keys,
    'controls',
  );
  _validatePlanMembership(
    manifest.plans.expand((plan) => plan.operationIds),
    operations.keys,
    'operations',
  );
  _validatePlanMembership(
    manifest.plans.expand((plan) => plan.scriptIds),
    scripts.keys,
    'scripts',
  );
  _validatePlanMembership(
    manifest.plans.expand((plan) => plan.automatedAcceptanceCriterionIds),
    criteria.keys,
    'automated acceptance criteria',
  );
  _validatePlanMembership(
    manifest.plans.expand((plan) => plan.requiredEvidenceIds),
    evidence.keys,
    'required Evidence',
  );
  _validatePlanMembership(
    manifest.plans.expand((plan) => plan.comparisonBindingIds),
    comparisons.keys,
    'comparison bindings',
  );
  _validatePlanMembership(
    manifest.plans.expand((plan) => plan.humanApprovalRequirementIds),
    approvals.keys,
    'human approval requirements',
  );
  _validatePlanMembership(
    manifest.plans.expand((plan) => plan.supplementalArtifactIds),
    supplemental.keys,
    'supplemental artifacts',
  );

  for (final plan in manifest.plans) {
    bool belongsToPlan(ScenarioId scenarioId) => scenarioId == plan.scenarioId;
    if (plan.controlIds.any((id) => !belongsToPlan(controls[id]!.scenarioId)) ||
        plan.operationIds.any(
          (id) => !belongsToPlan(operations[id]!.scenarioId),
        ) ||
        plan.scriptIds.any((id) => !belongsToPlan(scripts[id]!.scenarioId)) ||
        plan.automatedAcceptanceCriterionIds.any(
          (id) => !belongsToPlan(criteria[id]!.scenarioId),
        ) ||
        plan.requiredEvidenceIds.any(
          (id) => !belongsToPlan(evidence[id]!.scenarioId),
        ) ||
        plan.comparisonBindingIds.any(
          (id) => !belongsToPlan(comparisons[id]!.scenarioId),
        ) ||
        plan.humanApprovalRequirementIds.any(
          (id) => !belongsToPlan(approvals[id]!.scenarioId),
        ) ||
        plan.supplementalArtifactIds.any(
          (id) => !belongsToPlan(supplemental[id]!.scenarioId),
        )) {
      throw ArgumentError(
        'ScenarioLabPlan ${plan.scenarioId} crosses Scenarios',
      );
    }
    final planScripts = plan.scriptIds.map((id) => scripts[id]!);
    final usedOperations = planScripts
        .expand((script) => script.steps)
        .whereType<OperationScenarioScriptStep>()
        .map((step) => step.operationId)
        .toSet();
    final usedBindings = planScripts
        .expand((script) => script.steps)
        .whereType<ExecutionBindingScenarioScriptStep>()
        .map((step) => step.bindingId)
        .toSet();
    if (!_sameSet(usedOperations, plan.operationIds.toSet()) ||
        !_sameSet(usedBindings, plan.executionBindingIds.toSet())) {
      throw ArgumentError(
        'ScenarioLabPlan ${plan.scenarioId} allowlists must equal script use',
      );
    }
  }
}

void _validateComparisonInput(
  ComparisonInputReference input, {
  required bool isBaseline,
  required ScenarioComparisonBinding comparison,
  required RequiredEvidenceDefinition requirement,
  required Map<RequiredEvidenceId, RequiredEvidenceDefinition> evidence,
  required Map<SupplementalArtifactId, SupplementalArtifactReference>
  supplemental,
  required List<SupplementalArtifactId> referencedArtifacts,
}) {
  switch (input) {
    case ArtifactComparisonInputReference():
      final artifact = supplemental[input.artifactId];
      final expectedRole = isBaseline
          ? SupplementalArtifactRole.comparisonBaseline
          : SupplementalArtifactRole.comparisonCandidate;
      if (artifact == null ||
          artifact.scenarioId != comparison.scenarioId ||
          artifact.requiredEvidenceId != comparison.requiredEvidenceId ||
          artifact.role != expectedRole ||
          !requirement.allowedClassifications.contains(
            artifact.classification,
          )) {
        throw ArgumentError(
          'ScenarioComparisonBinding ${comparison.id} has an invalid artifact input',
        );
      }
      referencedArtifacts.add(input.artifactId);
    case EvidenceComparisonInputReference():
      if (!requirement.allowedClassifications.contains(input.classification)) {
        throw ArgumentError(
          'ScenarioComparisonBinding ${comparison.id} Evidence classification is not allowed',
        );
      }
    case RequiredEvidenceComparisonInputReference():
      if (input.requiredEvidenceId == comparison.requiredEvidenceId) {
        if (isBaseline) {
          throw ArgumentError(
            'ScenarioComparisonBinding ${comparison.id} current collection is candidate-only',
          );
        }
        return;
      }
      final source = evidence[input.requiredEvidenceId];
      if (source == null ||
          source.scenarioId != comparison.scenarioId ||
          !_sameComparisonPolicy(
            source.comparisonPolicy,
            requirement.comparisonPolicy,
          ) ||
          !requirement.allowedClassifications.containsAll(
            source.allowedClassifications,
          )) {
        throw ArgumentError(
          'ScenarioComparisonBinding ${comparison.id} has an incompatible required-Evidence input',
        );
      }
  }
}

void _validateRequiredEvidenceGraph(
  Iterable<ScenarioComparisonBinding> bindings,
) {
  final edges = <RequiredEvidenceId, Set<RequiredEvidenceId>>{};
  for (final binding in bindings) {
    final targets = <RequiredEvidenceId>{};
    for (final input in <ComparisonInputReference>[
      binding.baseline,
      binding.candidate,
    ]) {
      if (input is RequiredEvidenceComparisonInputReference) {
        if (input.requiredEvidenceId == binding.requiredEvidenceId) {
          continue;
        }
        targets.add(input.requiredEvidenceId);
      }
    }
    edges[binding.requiredEvidenceId] = targets;
  }

  final active = <RequiredEvidenceId>{};
  final complete = <RequiredEvidenceId>{};
  bool visit(RequiredEvidenceId id) {
    if (complete.contains(id)) return false;
    if (!active.add(id)) return true;
    for (final next in edges[id] ?? const <RequiredEvidenceId>{}) {
      if (visit(next)) return true;
    }
    active.remove(id);
    complete.add(id);
    return false;
  }

  for (final id in edges.keys) {
    if (visit(id)) {
      throw ArgumentError(
        'Required Evidence comparison references must form an acyclic graph',
      );
    }
  }
}

bool _sameComparisonPolicy(
  ComparisonPolicyReference left,
  ComparisonPolicyReference right,
) => left.kind == right.kind && left.policyId == right.policyId;

void _validatePlanMembership<T>(
  Iterable<T> memberships,
  Iterable<T> registry,
  String path,
) {
  final listed = memberships.toList(growable: false);
  final unique = listed.toSet();
  final expected = registry.toSet();
  if (listed.length != unique.length || !_sameSet(unique, expected)) {
    throw ArgumentError(
      'ScenarioLabPlan membership for $path must be exact and non-overlapping',
    );
  }
}

bool _sameSet<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

void _labId(String value, String kind) {
  if (value.length > 256) throw FormatException('$kind ID is too long');
  OpaqueId.validate(value, kind);
}

void _labText(String value, String path, {required int maxLength}) {
  if (value.isEmpty || value.length > maxLength) {
    throw ArgumentError('$path must be a bounded non-empty string');
  }
}

Map<String, Object?> _labObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _labOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

String _labString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 256,
}) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('$path.$key must be a bounded non-empty string');
  }
  return value;
}

String? _labOptionalString(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) return null;
  return _labString(json, key, path);
}

int _labInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

List<Object?> _labList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int minItems,
  required int maxItems,
}) {
  final value = json[key];
  if (value is! List<Object?> ||
      value.length < minItems ||
      value.length > maxItems) {
    throw FormatException('$path.$key must be a bounded array');
  }
  return value;
}

List<String> _labStringList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int minItems,
  required int maxItems,
}) {
  final raw = _labList(json, key, path, minItems: minItems, maxItems: maxItems);
  if (raw.any((item) => item is! String || item.isEmpty || item.length > 256)) {
    throw FormatException('$path.$key must contain bounded strings');
  }
  final values = raw.cast<String>();
  if (values.toSet().length != values.length) {
    throw FormatException('$path.$key must not contain duplicates');
  }
  return values;
}

T _labEnum<T extends Enum>(Iterable<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has an unsupported value: $name');
}

List<T> _labSorted<T>(
  Iterable<T> values,
  String Function(T) key,
  String path, {
  required int maxItems,
}) {
  final output = List<T>.of(values)
    ..sort((left, right) => key(left).compareTo(key(right)));
  if (output.length > maxItems ||
      output.map(key).toSet().length != output.length) {
    throw ArgumentError('$path identities must be unique and bounded');
  }
  return List<T>.unmodifiable(output);
}

List<T> _labSortedIds<T extends OpaqueId>(
  Iterable<T> values,
  String path, {
  required int minItems,
  required int maxItems,
}) {
  final output = List<T>.of(values)
    ..sort((left, right) => left.value.compareTo(right.value));
  if (output.length < minItems ||
      output.length > maxItems ||
      output.map((item) => item.value).toSet().length != output.length) {
    throw ArgumentError('$path IDs must be unique and bounded');
  }
  return List<T>.unmodifiable(output);
}
