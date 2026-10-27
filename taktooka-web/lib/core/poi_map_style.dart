const poiCategories = <String, List<String>>{
  'school': [
    'school',
    'education',
    'kindergarten',
    'secondary_school',
    'high_school',
  ],
  'college': ['college', 'university'],
  'mosque': [
    'mosque',
    'place-of-worship',
    'religious',
    'place_of_worship',
    'religious-muslim',
  ],
  'market': ['market', 'marketplace', 'grocery', 'supermarket'],
  'hospital': ['hospital', 'doctor', 'dentist', 'clinic'],
  'pharmacy': ['pharmacy'],
  'mall': ['mall', 'department-store', 'shopping-centre'],
  'shop': [
    'shop',
    'grocery',
    'supermarket',
    'clothing-store',
    'convenience',
    'bakery',
    'alcohol-shop',
    'furniture',
    'hardware',
    'jewelry',
    'butcher',
  ],
  'food': ['restaurant', 'cafe', 'fast-food', 'bar'],
};
const poiColors = <String, String>{
  'school': '#3478CA',
  'college': '#6558BF',
  'mosque': '#21856A',
  'market': '#BF791D',
  'hospital': '#E32946',
  'pharmacy': '#179A74',
  'mall': '#8056D9',
  'shop': '#ED871B',
  'food': '#D65D38',
  'place': '#388BCB',
};

List<dynamic> poiStyleValue({required bool icon}) => [
  'case',
  for (final entry in poiCategories.entries) ...[
    [
      'any',
      for (final field in ['maki', 'type', 'class'])
        ['in', field, ...entry.value],
    ],
    icon ? 'tkt-${entry.key}' : poiColors[entry.key],
  ],
  icon ? 'tkt-place' : poiColors['place'],
];

List<dynamic> mapNameExpression(String language) {
  final field = language == 'en'
      ? 'name_en'
      : language == 'ku'
      ? 'name_ku'
      : 'name_ar';
  return [
    'case',
    [
      '!=',
      [
        'coalesce',
        ['get', field],
        '',
      ],
      '',
    ],
    ['get', field],
    [
      'coalesce',
      ['get', 'name'],
      ['get', 'name_en'],
      '',
    ],
  ];
}

List<dynamic> poiVisibilityFilter() => [
  'any',
  [
    '>=',
    ['get', 'zoom'],
    14,
  ],
  [
    '<=',
    [
      'coalesce',
      ['get', 'filterrank'],
      0,
    ],
    2,
  ],
];
