/// Decodes a 17-character OBD-II VIN into human-readable fields.
class VinDecoder {
  VinDecoder._();

  /// Value used for any field that cannot be determined from the VIN
  /// (unassigned WMI / region, or a model year that is not encoded).
  static const unknown = 'Unknown';

  /// [now] is only used by the model-year heuristic for non-North-American
  /// VINs (defaults to the current date; injectable for tests).
  static Map<String, String> decode(String vin, {DateTime? now}) {
    if (vin.length < 17) return {'vin': vin, 'error': 'Incomplete VIN'};
    // ISO 3779: a VIN is exactly 17 characters.
    if (vin.length > 17) return {'vin': vin, 'error': 'Invalid VIN'};

    final v = vin.toUpperCase();
    return {
      'vin':          vin,
      'manufacturer': _manufacturer(v.substring(0, 3)),
      'country':      _country(v),
      'year':         _modelYear(v, now ?? DateTime.now()),
      'plant':        vin[10],
      'serial':       vin.substring(11),
    };
  }

  // ── Model year (position 10, char index 9) ────────────────────────────────
  // SAE J853: letters A-Y (skipping I, O, Q, U, Z) and digits 1-9.
  // The cycle repeats every 30 years: A=1980/2010, …, 9=2009/2039.
  static const _yearCodes = 'ABCDEFGHJKLMNPRSTVWXY123456789';

  // WMI regions assigned to North America (ISO 3780: 1, 4, 5, 7 United
  // States, 2 Canada, 3 Mexico / Central America / Puerto Rico). VINs from
  // these regions follow 49 CFR 565.15: position 10 is always the model year.
  static const _northAmerica = '123457';

  // ISO 3779 leaves position 10 free outside North America, and many
  // European makers use it for something else (Mercedes ECE: drive side
  // 1 = LHD / 2 = RHD; Renault/Dacia, PSA, Fiat, Ford of Europe, BMW: plant or
  // filler codes). The year is therefore only decoded for:
  //  * Japan (J), South Korea (K) and China (L, H). China's GB 16735 makes
  //    position 10 the model year (and position 9 a check digit); Japanese and
  //    Korean makers use the SAE model-year code in their export VINs.
  //  * The WMIs below, whose makers encode position 10 in every market.
  // Chinese brands built elsewhere (GWM Thailand MNU, Haval Russia XZG) and
  // Proton (PL1, Malaysia) are not covered by GB 16735 and no source shows
  // them encoding position 10, so their year stays Unknown.
  static const _yearRegions = 'JKLH';
  static const _yearWmis = {
    // Volkswagen group
    'WVW', 'WVG', 'WV1', 'WV2', 'WAU', 'WA1', 'WUA', 'WP0', 'WP1',
    'TMB', 'VSS',
    // Volvo Cars, Saab
    'YV1', 'YV4', 'YS3',
    // Jaguar Land Rover
    'SAJ', 'SAD', 'SAL',
    // Toyota Motor Thailand (Hilux / Fortuner)
    'MR0',
  };
  // Inside a year region but built to European rules.
  static const _noYearWmis = {
    'JMZ', // Mazda for Europe export
  };

  static String _modelYear(String vin, DateTime now) {
    final i = _yearCodes.indexOf(vin[9]);
    if (i == -1) return unknown;

    // 49 CFR 565.15 (North American light vehicles): position 7 numeric →
    // 1980–2009 cycle, alphabetic → 2010–2039 cycle.
    if (_northAmerica.contains(vin[0])) {
      final pos7Alpha = RegExp('[A-Z]').hasMatch(vin[6]);
      return '${(pos7Alpha ? 2010 : 1980) + i}';
    }

    final wmi = vin.substring(0, 3);
    final encoded = _yearWmis.contains(wmi) ||
        (_yearRegions.contains(vin[0]) && !_noYearWmis.contains(wmi));
    if (!encoded) return unknown;

    // Position 7 carries no year information here. Prefer the recent cycle
    // unless it lies in the future (a model year can be at most one year
    // ahead of the calendar), e.g. '7' → 2007 rather than 2037.
    final recent = 2010 + i;
    return '${recent > now.year + 1 ? recent - 30 : recent}';
  }

  // ── Country (ISO 3780 region, first one or two VIN characters) ────────────

  // Character order ISO 3780 uses for two-character ranges (no I, O, Q).
  static const _isoOrder = 'ABCDEFGHJKLMNPRSTUVWXYZ1234567890';

  // Regions split by the second character (ISO 3780 WMI country code chart,
  // revised 2021-04-13), so the first character alone is ambiguous there
  // (e.g. SA–SM UK but SU–SZ Poland; MA–ME India but ML–MR Thailand).
  // (first char, second-char range, country). Unlisted ranges are unassigned.
  static const _twoCharRanges = <(String, String, String, String)>[
    // Africa
    ('A', 'A', 'H', 'South Africa'),   ('A', 'J', 'K', 'Ivory Coast'),
    ('A', 'L', 'M', 'Lesotho'),        ('A', 'N', 'P', 'Botswana'),
    ('A', 'R', 'S', 'Namibia'),        ('A', 'T', 'U', 'Madagascar'),
    ('A', 'V', 'W', 'Mauritius'),      ('A', 'X', 'Y', 'Tunisia'),
    ('A', 'Z', '1', 'Cyprus'),         ('A', '2', '3', 'Zimbabwe'),
    ('A', '4', '5', 'Mozambique'),
    ('B', 'A', 'B', 'Angola'),         ('B', 'C', 'C', 'Ethiopia'),
    ('B', 'F', 'G', 'Kenya'),          ('B', 'H', 'H', 'Rwanda'),
    ('B', 'L', 'L', 'Nigeria'),        ('B', 'R', 'R', 'Algeria'),
    ('B', 'T', 'T', 'Eswatini'),       ('B', 'U', 'U', 'Uganda'),
    ('B', '3', '4', 'Libya'),
    ('C', 'A', 'B', 'Egypt'),          ('C', 'F', 'G', 'Morocco'),
    ('C', 'L', 'M', 'Zambia'),
    // Asia
    ('K', 'F', 'H', 'Israel'),         ('K', 'L', 'R', 'South Korea'),
    ('K', 'S', 'T', 'Jordan'),         ('K', '1', '3', 'South Korea'),
    ('K', '5', '5', 'Kyrgyzstan'),
    ('M', 'A', 'E', 'India'),          ('M', 'F', 'K', 'Indonesia'),
    ('M', 'L', 'R', 'Thailand'),       ('M', 'S', 'S', 'Myanmar'),
    ('M', 'U', 'U', 'Mongolia'),       ('M', 'X', 'X', 'Kazakhstan'),
    ('M', 'Y', '0', 'India'),
    ('N', 'A', 'E', 'Iran'),           ('N', 'F', 'G', 'Pakistan'),
    ('N', 'J', 'J', 'Iraq'),           ('N', 'L', 'R', 'Turkey'),
    ('N', 'S', 'T', 'Uzbekistan'),     ('N', 'V', 'V', 'Azerbaijan'),
    ('N', 'X', 'X', 'Tajikistan'),     ('N', 'Y', 'Y', 'Armenia'),
    ('N', '1', '5', 'Iran'),           ('N', '7', '8', 'Turkey'),
    ('P', 'A', 'C', 'Philippines'),    ('P', 'F', 'G', 'Singapore'),
    ('P', 'L', 'R', 'Malaysia'),       ('P', 'S', 'T', 'Bangladesh'),
    ('P', '5', '0', 'India'),
    ('R', 'A', 'B', 'United Arab Emirates'), ('R', 'F', 'K', 'Taiwan'),
    ('R', 'L', 'N', 'Vietnam'),        ('R', 'P', 'P', 'Laos'),
    ('R', 'S', 'T', 'Saudi Arabia'),   ('R', '1', '7', 'Hong Kong'),
    // Europe
    ('S', 'A', 'M', 'United Kingdom'), ('S', 'N', 'T', 'Germany'),
    ('S', 'U', 'Z', 'Poland'),         ('S', '1', '2', 'Latvia'),
    ('S', '3', '3', 'Georgia'),        ('S', '4', '4', 'Iceland'),
    ('T', 'A', 'H', 'Switzerland'),    ('T', 'J', 'P', 'Czech Republic'),
    ('T', 'R', 'V', 'Hungary'),        ('T', 'W', '2', 'Portugal'),
    ('T', '3', '5', 'Serbia'),         ('T', '6', '6', 'Andorra'),
    ('T', '7', '8', 'Netherlands'),
    ('U', 'A', 'C', 'Spain'),          ('U', 'H', 'M', 'Denmark'),
    ('U', 'N', 'R', 'Ireland'),        ('U', 'U', 'X', 'Romania'),
    ('U', '1', '2', 'North Macedonia'), ('U', '5', '7', 'Slovakia'),
    ('U', '8', '0', 'Bosnia and Herzegovina'),
    ('V', 'A', 'E', 'Austria'),        ('V', 'F', 'R', 'France'),
    ('V', 'S', 'W', 'Spain'),          ('V', 'X', '2', 'France'),
    ('V', '3', '5', 'Croatia'),        ('V', '6', '8', 'Estonia'),
    ('X', 'A', 'C', 'Bulgaria'),       ('X', 'D', 'E', 'Russia'),
    ('X', 'F', 'H', 'Greece'),         ('X', 'J', 'K', 'Russia'),
    ('X', 'L', 'R', 'Netherlands'),    ('X', 'S', 'W', 'Russia'),
    ('X', 'X', 'Y', 'Luxembourg'),     ('X', 'Z', '0', 'Russia'),
    ('Y', 'A', 'E', 'Belgium'),        ('Y', 'F', 'K', 'Finland'),
    ('Y', 'N', 'N', 'Malta'),          ('Y', 'S', 'W', 'Sweden'),
    ('Y', 'X', '2', 'Norway'),         ('Y', '3', '5', 'Belarus'),
    ('Y', '6', '9', 'Ukraine'),
    ('Z', 'A', 'U', 'Italy'),          ('Z', 'X', 'Z', 'Slovenia'),
    ('Z', '1', '1', 'San Marino'),     ('Z', '3', '5', 'Lithuania'),
    ('Z', '6', '0', 'Russia'),
    // North America (3 = Mexico + Central America), Oceania, South America
    ('3', 'A', 'X', 'Mexico'),         ('3', '4', '4', 'Nicaragua'),
    ('3', '5', '5', 'Dominican Republic'), ('3', '6', '6', 'Honduras'),
    ('3', '7', '7', 'Panama'),         ('3', '8', '9', 'Puerto Rico'),
    ('6', 'A', 'X', 'Australia'),      ('6', 'Y', '1', 'New Zealand'),
    ('8', 'A', 'E', 'Argentina'),      ('8', 'F', 'G', 'Chile'),
    ('8', 'L', 'N', 'Ecuador'),        ('8', 'S', 'W', 'Peru'),
    ('8', 'X', 'Z', 'Venezuela'),      ('8', '2', '2', 'Bolivia'),
    ('8', '4', '4', 'Costa Rica'),
    ('9', 'A', 'E', 'Brazil'),         ('9', 'F', 'G', 'Colombia'),
    ('9', 'S', 'V', 'Uruguay'),        ('9', '1', '0', 'Brazil'),
  ];

  static String _country(String vin) {
    final first = vin[0];
    final second = _isoOrder.indexOf(vin[1]);
    var splitRegion = false;
    for (final (c, from, to, country) in _twoCharRanges) {
      if (c != first) continue;
      splitRegion = true;
      if (second >= _isoOrder.indexOf(from) && second <= _isoOrder.indexOf(to)) {
        return country;
      }
    }
    if (splitRegion) return unknown;

    // Rows dedicated to a single country (D, F, G and 0 are unassigned).
    const map = {
      'E': 'Russia', 'H': 'China', 'J': 'Japan', 'L': 'China',
      'W': 'Germany',
      '1': 'United States', '2': 'Canada', '4': 'United States',
      '5': 'United States', '7': 'United States',
    };
    return map[first] ?? unknown;
  }

  // ── Manufacturer from WMI (first 3 chars) ─────────────────────────────────
  // Sources: NHTSA vPIC (DecodeWMI), the ISO 3780 / SAE J1044 based WMI list
  // on Wikipedia ("Vehicle identification number") and Wikibooks' WMI list.
  static String _manufacturer(String wmi) {
    const map = {
      // Japanese
      'JHM': 'Honda',      'JHL': 'Honda',
      'JTD': 'Toyota',     'JTE': 'Toyota',   'JTM': 'Toyota',
      'JTN': 'Toyota',     'JTJ': 'Lexus',    'JTH': 'Lexus',
      'JN1': 'Nissan',     'JN8': 'Nissan',   'JF1': 'Subaru',
      'JF2': 'Subaru',     'JM1': 'Mazda',    'JMZ': 'Mazda',
      'JA3': 'Mitsubishi', 'JA4': 'Mitsubishi', 'JMY': 'Mitsubishi',
      'JS1': 'Suzuki',     'JS2': 'Suzuki',   'JS3': 'Suzuki',
      'JMB': 'Mitsubishi', 'JT3': 'Toyota',
      // Korean
      'KMH': 'Hyundai',    'KM8': 'Hyundai',  'KMJ': 'Hyundai',
      'KNA': 'Kia',        'KND': 'Kia',      'KNM': 'Renault Samsung',
      'KL1': 'Chevrolet (GM Korea)',
      // Korean brands built abroad
      'MAL': 'Hyundai',    '5NP': 'Hyundai',  'TMA': 'Hyundai',
      'NLH': 'Hyundai',    'LBE': 'Hyundai',  'U5Y': 'Kia',
      // Chinese (ISO 3780 rows L and H). Every entry below is on the
      // Wikibooks WMI list; most are also on Wikipedia's list or in vPIC.
      'LS5': 'Changan',    'LSJ': 'SAIC MG',  'L6T': 'Geely',
      'LVV': 'Chery',
      // GWM's umbrella WMI: Haval, Tank, Wey, Ora and the Poer/Wingle pickups.
      'LGW': 'Great Wall Motor (GWM)',
      'MNU': 'Great Wall Motor (GWM)',   // GWM Thailand (Rayong)
      'XZG': 'Haval (Great Wall Motor)', // Haval Motor Rus (Tula)
      'LVS': 'Ford (Changan)', 'LSV': 'Volkswagen China',
      'LB3': 'Geely',      'LMG': 'GAC',      'L10': 'Geely', // Emgrand brand
      // Changan group
      'LS4': 'Changan',    'LSC': 'Changan',  // MPV/SUV, light truck
      'LS6': 'Changan (Deepal/Avatr)',
      'LVR': 'Mazda (Changan)',
      // Jiangling (JMC) and its Ford joint venture
      'LEF': 'JMC',        'LJX': 'Ford (JMC)', 'LXW': 'Ford (JMC)',
      // Chery group
      'LVT': 'Chery (Exeed/Jetour)',
      'LVU': 'Chery (Jetour/Omoda/Jaecoo)',
      'LNN': 'Chery (Omoda/Jaecoo)',
      'HJR': 'Jetour (Chery)',  // Chery Commercial Vehicle (Anhui)
      'LVM': 'Chery Commercial',
      'L2C': 'Chery Jaguar Land Rover',
      // BAIC, JAC, FAW
      'LNB': 'BAIC',       'LJ1': 'JAC / Nio', // Nio cars are built by JAC
      'LFP': 'FAW (Hongqi/Bestune)', 'LFB': 'FAW',
      // Dongfeng
      'LDP': 'Dongfeng (Aeolus/Voyah)', 'LGJ': 'Dongfeng (Aeolus)',
      'LGG': 'Dongfeng (Forthing)',     'LMX': 'Dongfeng (Forthing)',
      // BYD, GAC Aion
      'LC0': 'BYD',        'LGX': 'BYD',      'LPE': 'BYD',
      'LNA': 'GAC Aion',
      // Malaysia
      'PL1': 'Proton',
      // German
      'WBA': 'BMW',        'WBS': 'BMW M',    'WBY': 'BMW',
      'WMW': 'MINI',       'WAP': 'Alpina',
      'WDB': 'Mercedes',   'WDD': 'Mercedes', 'WDC': 'Mercedes',
      'W1K': 'Mercedes',   'W1N': 'Mercedes', 'W1V': 'Mercedes',
      'WDF': 'Mercedes',   '4JG': 'Mercedes',
      'WVW': 'Volkswagen', 'WVG': 'Volkswagen',
      'WV1': 'Volkswagen', 'WV2': 'Volkswagen',
      'WAU': 'Audi',       'WA1': 'Audi',     'WUA': 'Audi',
      'WP0': 'Porsche',    'WP1': 'Porsche',
      'W0L': 'Opel',       'WF0': 'Ford',
      // American
      '1G1': 'Chevrolet',  '1G2': 'Pontiac',  '1G6': 'Cadillac',
      '1GC': 'Chevrolet',  '1GN': 'Chevrolet', '1GT': 'GMC',
      '1GK': 'GMC',        '1GY': 'Cadillac',
      '2GC': 'Chevrolet',  '2GT': 'GMC',
      '3GC': 'Chevrolet',  '3GN': 'Chevrolet',
      '1FA': 'Ford',       '1FB': 'Ford',     '1FC': 'Ford',
      '1FD': 'Ford',       '1FM': 'Ford',     '1FT': 'Ford',
      '1C3': 'Chrysler/Dodge', '1C4': 'Chrysler/Jeep/Dodge',
      '1J4': 'Jeep',       '1J8': 'Jeep',
      '1C6': 'Ram',        '3C6': 'Ram',      '3D7': 'Dodge',
      '2C3': 'Chrysler/Dodge', '3C4': 'Chrysler/Dodge',
      '2FM': 'Ford',       '1LN': 'Lincoln',  '5LM': 'Lincoln',
      '1G4': 'Buick',      '2GN': 'Chevrolet', '2GK': 'GMC',
      '5YJ': 'Tesla',
      '1HG': 'Honda',      '1N4': 'Nissan',
      '1NX': 'Toyota',     '1VW': 'Volkswagen', '1YV': 'Mazda',
      '2HG': 'Honda',      '2T1': 'Toyota',   '3FA': 'Ford Mexico',
      '3VW': 'Volkswagen Mexico',
      '4US': 'BMW',        '5UX': 'BMW',
      // Swedish
      'YV1': 'Volvo',      'YV4': 'Volvo',    'YS3': 'SAAB',
      // Italian
      'ZAR': 'Alfa Romeo', 'ZFF': 'Ferrari',  'ZHW': 'Lamborghini',
      'ZLA': 'Lancia',     'ZFA': 'Fiat',     'ZAM': 'Maserati',
      // French
      'VF1': 'Renault',    'VF3': 'Peugeot',  'VF7': 'Citroën',
      // Czech, Spanish
      'TMB': 'Škoda',      'VSS': 'SEAT',
      // British
      'SAJ': 'Jaguar',     'SAD': 'Jaguar',   'SAL': 'Land Rover',
      'SAR': 'Rover',      'SCB': 'Bentley',  'SCC': 'Lotus',
      'SCF': 'Aston Martin', 'SDB': 'Talbot',
      'SFD': 'Alexander Dennis', 'SCA': 'Rolls-Royce',
      // Others
      'NMT': 'Toyota Turkey', 'NM0': 'Ford Turkey',
      'MAJ': 'Ford India',   'MBJ': 'Toyota India',
      'MR0': 'Toyota',     'MHF': 'Toyota',   'MMB': 'Mitsubishi',
      'MNT': 'Nissan',     'MRH': 'Honda',    'MPA': 'Isuzu',
      'UU1': 'Dacia',
    };

    return map[wmi] ?? unknown;
  }
}
