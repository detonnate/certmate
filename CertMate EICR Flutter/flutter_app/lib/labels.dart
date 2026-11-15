const labels = {
  'descriptionText': 'Description',
  'ze': 'External earth fault loop impedance (Ze)',
  'pfc': 'Prospective fault current (PFC / PSCC)',
  'liveCSA': 'Live CSA (mm²)',
  'cpcCSA': 'CPC CSA (mm²)',
  'r1r2': 'R1 + R2 (Ω)',
  'r2': 'R2 (Ω)',
  'maxZs': 'Maximum Zs (Ω)',
  'measuredZs': 'Measured Zs (Ω)',
  'insulationLL': 'Insulation L–L (MΩ)',
  'insulationLN': 'Insulation L–N (MΩ)',
  'insulationLE': 'Insulation L–E (MΩ)',
  'insulationNE': 'Insulation N–E (MΩ)',
  'rcdHalf': 'RCD ½ × IΔn',
  'rcdOne': 'RCD 1 × IΔn (ms)',
  'rcdFive': 'RCD 5 × IΔn (ms)',
  'afddFitted': 'AFDD fitted',
  'spdProtected': 'SPD protected',
  'spdFitted': 'SPD fitted',
  'spdPresent': 'SPD present',
  'spdType': 'SPD type',
  'rcdType': 'RCD type',
  'rcdRating': 'RCD rating',
  'rcdPresent': 'RCD present',
};

String label(String field) =>
    labels[field] ??
    '${field[0].toUpperCase()}${field.substring(1).replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match[0]!.toLowerCase()}')}';

const choices = {
  'premisesType': ['Domestic', 'Commercial', 'Industrial', 'Other'],
  'overallAssessment': ['Not Assessed', 'Satisfactory', 'Unsatisfactory'],
  'classification': ['C1', 'C2', 'C3', 'FI'],
  'result': ['✓', 'N/A', 'LIM', 'C1', 'C2', 'C3', 'FI'],
  'polarity': ['Pass', 'Fail', 'N/A'],
  'functionalTest': ['Pass', 'Fail', 'N/A'],
  'protectiveDeviceCurve': ['B', 'C', 'D'],
};
