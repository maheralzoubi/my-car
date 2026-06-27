/// Decodes a 17-character OBD-II VIN into human-readable fields.
class VinDecoder {
  VinDecoder._();

  static Map<String, String> decode(String vin) {
    if (vin.length < 17) return {'vin': vin, 'error': 'Incomplete VIN'};

    return {
      'vin':          vin,
      'manufacturer': _manufacturer(vin.substring(0, 3)),
      'country':      _country(vin[0]),
      'year':         _modelYear(vin[9]),
      'plant':        vin[10],
      'serial':       vin.substring(11),
    };
  }

  // ── Model year (position 10, char index 9) ────────────────────────────────
  // SAE J17: letters A-Y (skipping I, O, Q, U, Z) and digits 1-9.
  // The cycle repeats: A=1980/2010, B=1981/2011, …, 9=2009/2039.
  // We use the 2010+ interpretation for modern vehicles.
  static String _modelYear(String c) {
    const map = {
      'A': '2010', 'B': '2011', 'C': '2012', 'D': '2013', 'E': '2014',
      'F': '2015', 'G': '2016', 'H': '2017', 'J': '2018', 'K': '2019',
      'L': '2020', 'M': '2021', 'N': '2022', 'P': '2023', 'R': '2024',
      'S': '2025', 'T': '2026', 'V': '2027', 'W': '2028', 'X': '2029',
      'Y': '2030',
      '1': '2031', '2': '2032', '3': '2033', '4': '2034', '5': '2035',
      '6': '2036', '7': '2037', '8': '2038', '9': '2039',
    };
    return map[c.toUpperCase()] ?? c;
  }

  // ── Country from first VIN character ──────────────────────────────────────
  static String _country(String c) {
    const map = {
      'A': 'South Africa', 'B': 'Angola', 'C': 'Benin', 'D': 'Egypt',
      'E': 'Ethiopia', 'F': 'Ghana', 'G': 'Ivory Coast', 'H': 'Kenya',
      'J': 'Japan', 'K': 'South Korea', 'L': 'China', 'M': 'India',
      'N': 'Turkey', 'P': 'Philippines',
      'R': 'Taiwan', 'S': 'United Kingdom',
      'T': 'Czech Republic', 'U': 'Poland', 'V': 'France/Austria',
      'W': 'Germany', 'X': 'Russia/Georgia',
      'Y': 'Sweden/Finland', 'Z': 'Italy',
      '1': 'United States', '2': 'Canada', '3': 'Mexico',
      '4': 'United States', '5': 'United States',
      '6': 'Australia/New Zealand', '7': 'New Zealand',
      '8': 'Argentina/Chile', '9': 'Brazil',
    };
    return map[c.toUpperCase()] ?? 'Unknown';
  }

  // ── Manufacturer from WMI (first 3 chars) ─────────────────────────────────
  static String _manufacturer(String wmi) {
    const map = {
      // Japanese
      'JHM': 'Honda',      'JTD': 'Toyota',   'JTJ': 'Lexus',
      'JN1': 'Nissan',     'JN8': 'Nissan',   'JF1': 'Subaru',
      'JF2': 'Subaru',     'JM1': 'Mazda',    'JA3': 'Mitsubishi',
      'JS1': 'Suzuki',     'JS2': 'Suzuki',
      // Korean
      'KMH': 'Hyundai',    'KNA': 'Kia',      'KNM': 'Renault Samsung',
      // German
      'WBA': 'BMW',        'WBS': 'BMW M',    'WBY': 'BMW',
      'WDB': 'Mercedes',   'WDD': 'Mercedes', 'WDC': 'Mercedes',
      'WVW': 'Volkswagen', 'WV1': 'Volkswagen', 'WV2': 'Volkswagen',
      'WAU': 'Audi',       'WAP': 'Porsche',  'WP0': 'Porsche',
      'WP1': 'Porsche',    'W0L': 'Opel',
      // American
      '1G1': 'Chevrolet',  '1G2': 'Pontiac',  '1G6': 'Cadillac',
      '1FA': 'Ford',       '1FB': 'Ford',     '1FC': 'Ford',
      '1FD': 'Ford',       '1FT': 'Ford',     '1GC': 'Chevrolet',
      '1GT': 'Chevrolet',  '1HG': 'Honda',    '1N4': 'Nissan',
      '1NX': 'Toyota',     '1VW': 'Volkswagen', '1YV': 'Mazda',
      '2HG': 'Honda',      '2T1': 'Toyota',   '3FA': 'Ford Mexico',
      '3VW': 'Volkswagen Mexico',
      // Swedish
      'YV1': 'Volvo',      'YV4': 'Volvo',    'YS3': 'SAAB',
      // Italian
      'ZAR': 'Alfa Romeo', 'ZFF': 'Ferrari',  'ZHW': 'Lamborghini',
      'ZLA': 'Lancia',     'ZCA': 'Fiat',
      // French
      'VF1': 'Renault',    'VF3': 'Peugeot',  'VF7': 'Citroën',
      // British
      'SAJ': 'Jaguar',     'SAL': 'Land Rover', 'SAR': 'Rover',
      'SCB': 'Bentley',    'SCC': 'Lotus',    'SDB': 'Aston Martin',
      'SFD': 'Alexander Dennis',
      // Others
      'NMT': 'Toyota Turkey', 'NM0': 'Ford Turkey',
      'MAJ': 'Ford India',   'MBJ': 'Toyota India',
      'LVS': 'Volvo China',  'LSV': 'Volkswagen China',
    };

    // Try full WMI first, then first 2 chars
    return map[wmi.toUpperCase()] ??
        map[wmi.substring(0, 2).toUpperCase()] ??
        'Unknown';
  }
}
