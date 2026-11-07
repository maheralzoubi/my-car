import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/vin_decoder.dart';

import '../helpers/elm327_sim.dart';

// VIN fixtures. Every 17-char fixture below has a valid ISO 3779 / 49 CFR 565
// check digit at position 9, so they are structurally real VINs.
//
//   2003 Honda Accord (USA)       1HGCM82633A004352  — WMI 1HG, pos-7 numeric
//   2019 Ford Taurus (USA)        1FAHP2E86KG100001  — WMI 1FA, plant G=Chicago
//   2022 Ford Taurus (China/GCC)  LVSHFFAC1NF100001  — WMI LVS = Changan Ford
//   2020 Ford Explorer (USA)      1FMSK8DHXLGA00001  — WMI 1FM = Ford MPV/SUV
const _accord2003 = '1HGCM82633A004352';
const _taurus2019 = '1FAHP2E86KG100001';
const _taurus2022 = 'LVSHFFAC1NF100001';
const _explorer2020 = '1FMSK8DHXLGA00001';

void main() {
  // ── Valid VINs ─────────────────────────────────────────────────────────────

  group('decode — valid 17-char VINs', () {
    test('2019 US-built Ford Taurus decodes all fields', () {
      final r = VinDecoder.decode(_taurus2019);

      expect(r.containsKey('error'), isFalse);
      expect(r['vin'], _taurus2019);
      expect(r['manufacturer'], 'Ford');
      expect(r['country'], 'United States');
      expect(r['year'], '2019'); // position 10 = 'K'
      expect(r['plant'], 'G'); // position 11
      expect(r['serial'], '100001'); // positions 12-17
    });

    test('2022 Ford Taurus (China-built, GCC market) — year and country', () {
      final r = VinDecoder.decode(_taurus2022);

      expect(r.containsKey('error'), isFalse);
      expect(r['year'], '2022'); // position 10 = 'N'
      expect(r['country'], 'China'); // position 1 = 'L'
      expect(r['plant'], 'F');
      expect(r['serial'], '100001');
    });

    test(
      '2022 Ford Taurus (China-built) — WMI LVS is Changan Ford',
      () {
        final r = VinDecoder.decode(_taurus2022);
        expect(r['manufacturer'], contains('Ford'));
      },
    );

    test(
      '2020 Ford Explorer — WMI 1FM (Ford MPV/SUV) is recognised',
      () {
        final r = VinDecoder.decode(_explorer2020);
        expect(r['manufacturer'], 'Ford');
        expect(r['year'], '2020');
      },
    );

    test('decodes manufacturers from several regions', () {
      expect(VinDecoder.decode('JHMCM56557C404453')['manufacturer'], 'Honda');
      expect(VinDecoder.decode('WBA3A5C51CF256551')['manufacturer'], 'BMW');
      expect(VinDecoder.decode('KMHDH4AE1DU123456')['manufacturer'], 'Hyundai');
      expect(VinDecoder.decode('YV1MS382062123456')['manufacturer'], 'Volvo');
      expect(VinDecoder.decode('SALGA2EF8EA123456')['manufacturer'],
          'Land Rover');
    });

    test('country is taken from position 1 (ISO 3780 region)', () {
      expect(VinDecoder.decode('1HGCM82633A004352')['country'],
          'United States');
      expect(VinDecoder.decode('2HGFG12648H500000')['country'], 'Canada');
      expect(VinDecoder.decode('3FAHP0HA6AR100000')['country'], 'Mexico');
      expect(VinDecoder.decode('JHMCM56557C404453')['country'], 'Japan');
      expect(VinDecoder.decode('KMHDH4AE1DU123456')['country'], 'South Korea');
      expect(VinDecoder.decode('WBA3A5C51CF256551')['country'], 'Germany');
      expect(VinDecoder.decode('SALGA2EF8EA123456')['country'],
          'United Kingdom');
      expect(VinDecoder.decode('9BWZZZ377VT004251')['country'], 'Brazil');
    });

    test('country code U (UU–UX) is Romania, e.g. Dacia/Renault Logan UU1',
        () {
      expect(VinDecoder.decode('UU1LSDAEH45123456')['country'], 'Romania');
    });

    test('European regions are split by the second character (ISO 3780)', () {
      // Same first letter, different country.
      expect(VinDecoder.decode('SUUAW3BR5JS123456')['country'], 'Poland');
      expect(VinDecoder.decode('SALGA2EF8EA123456')['country'],
          'United Kingdom');
      expect(VinDecoder.decode('TMBJJ7NE8J0123456')['country'],
          'Czech Republic');
      expect(VinDecoder.decode('TRUZZZ8J181123456')['country'], 'Hungary');
      expect(VinDecoder.decode('VF1RFB00X57123456')['country'], 'France');
      expect(VinDecoder.decode('VSSZZZ6JZ9R123456')['country'], 'Spain');
      expect(VinDecoder.decode('YV1MS382062123456')['country'], 'Sweden');
      expect(VinDecoder.decode('YS3FD49Y581123456')['country'], 'Sweden');
      expect(VinDecoder.decode('XTA21140054123456')['country'], 'Russia');
      expect(VinDecoder.decode('UH1AA11B1NA000001')['country'], 'Denmark');
      // UA-UG has no single-country default any more (U was "Poland").
      expect(VinDecoder.decode('UE1AA11B1NA000001')['country'], 'Unknown');
    });

    test('unknown North American WMI: "Unknown" make, year still decoded',
        () {
      // '1ZZ' is not an assigned WMI, but every WMI-1 VIN follows 49 CFR 565.
      final r = VinDecoder.decode('1ZZAA1AB1NA000001');
      expect(r['manufacturer'], 'Unknown');
      expect(r['country'], 'United States');
      expect(r['year'], '2022');
    });

    test('unknown European WMI: "Unknown" make and year', () {
      // Previously expected Italy / 2022, which encoded two bugs: ISO 3780
      // gives ZX–ZZ to Slovenia (Italy is ZA–ZU), and outside North America
      // position 10 is only a model year for makers known to encode it, which
      // an unassigned WMI is not.
      final r = VinDecoder.decode('ZZZAA11B1NA000001');
      expect(r['manufacturer'], 'Unknown');
      expect(r['country'], 'Slovenia');
      expect(r['year'], 'Unknown');
      expect(r['year'], VinDecoder.unknown);
    });

    test('unknown region character yields "Unknown" country', () {
      // '0' is not assigned to any region in ISO 3780.
      expect(VinDecoder.decode('0HGCM82633A004352')['country'], 'Unknown');
    });

    test('lowercase input still resolves manufacturer, country and year', () {
      final r = VinDecoder.decode(_taurus2019.toLowerCase());
      expect(r['manufacturer'], 'Ford');
      expect(r['country'], 'United States');
      expect(r['year'], '2019');
    });
  });

  // ── Model year (position 10) ───────────────────────────────────────────────

  group('decode — model year', () {
    // A 2010–2039 cycle VIN template with alphabetic position 7 ('E').
    String withYear(String c) => '1FAHP2E86${c}G100001';

    test('maps the 2010+ letter cycle per SAE J853 (skips I, O, Q, U, Z)', () {
      const expected = {
        'A': '2010', 'B': '2011', 'C': '2012', 'D': '2013', 'E': '2014',
        'F': '2015', 'G': '2016', 'H': '2017', 'J': '2018', 'K': '2019',
        'L': '2020', 'M': '2021', 'N': '2022', 'P': '2023', 'R': '2024',
        'S': '2025', 'T': '2026', 'V': '2027', 'W': '2028', 'X': '2029',
        'Y': '2030',
      };
      expected.forEach((code, year) {
        expect(VinDecoder.decode(withYear(code))['year'], year,
            reason: 'year code $code');
      });
    });

    test('characters never used for model year do not decode to a year', () {
      for (final c in ['I', 'O', 'Q', 'U', 'Z', '0']) {
        expect(VinDecoder.decode(withYear(c))['year'],
            isNot(matches(RegExp(r'^\d{4}$'))),
            reason: '"$c" is not a valid model-year code');
      }
    });

    test('numeric position 7 selects the 1980–2009 cycle (49 CFR 565.15)',
        () {
      // 2003 Honda Accord: position 7 = '2' (numeric), position 10 = '3'.
      expect(VinDecoder.decode(_accord2003)['year'], '2003');
      // Same VIN shape with alphabetic position 7 → 2010+ cycle.
      expect(VinDecoder.decode('1HGCM8A633A004352')['year'], '2033');
      // Numeric position 7, letter year: 'Y' → 2000, 'A' → 1980.
      String withYear(String c) => _accord2003.replaceRange(9, 10, c);
      expect(VinDecoder.decode(withYear('Y'))['year'], '2000');
      expect(VinDecoder.decode(withYear('A'))['year'], '1980');
    });

    test('North American VINs (WMI 1-5) all follow the position 7 rule', () {
      // 2008 Honda Civic (Canada): position 7 '6', position 10 '8'.
      expect(VinDecoder.decode('2HGFG12648H500000')['year'], '2008');
      // 2010 Ford Fusion (Mexico): position 7 'H' (letter), position 10 'A'.
      expect(VinDecoder.decode('3FAHP0HA6AR100000')['year'], '2010');
    });

    group('outside North America (no position 7 rule)', () {
      final now = DateTime(2026, 11, 2);
      String year(String vin) => VinDecoder.decode(vin, now: now)['year']!;
      // VW group encodes the model year at position 10 in every market. (These
      // cases used a European BMW VIN before; BMW is no longer trusted to do
      // so outside North America — see the year-rule group below.)
      String vw(String c) => 'WVWZZZ1KZ${c}W123456';

      test('digit year codes are 2001–2009, not future 2031–2039', () {
        // 2007 Honda (Japan), position 7 numeric.
        expect(year('JHMCM56557C404453'), '2007');
        // Position 7 alphabetic does not push a European VIN into the 2030s.
        expect(year(vw('6')), '2006');
      });

      test('letter year codes take the 2010 cycle up to next year', () {
        expect(year(vw('C')), '2012');
        expect(year(_taurus2022), '2022');
        // 'T' = 2026 (this year), 'V' = 2027 (next model year).
        expect(year(vw('T')), '2026');
        expect(year(vw('V')), '2027');
      });

      test('letter codes more than a year ahead fall back 30 years', () {
        // 'W' would be 2028 → 1998; 'Y' would be 2030 → 2000.
        expect(year(vw('W')), '1998');
        expect(year(vw('Y')), '2000');
      });
    });

    group('which VINs carry a model year at position 10', () {
      final now = DateTime(2026, 11, 3);
      String year(String vin) => VinDecoder.decode(vin, now: now)['year']!;

      test('North America (WMI 1-5, 7): always, via 49 CFR 565.15', () {
        expect(year('5UXZV8C57DL123456'), '2013'); // BMW Spartanburg
        expect(year('4USBT53544LT12345'), '2004'); // BMW USA, pos 7 numeric
        expect(year('3C6UR5DL0KG561037'), '2019'); // Ram, Mexico
        expect(year('2GCEK19T4X1234567'), '1999'); // Chevrolet, Canada
        expect(year('7SAYGDEE1NF123456'), '2022'); // WMI 7 = United States
      });

      test('Japan, Korea, China: decoded (SAE code in export VINs, GB 16735)',
          () {
        expect(year('JTMHY7AJ6M4123456'), '2021'); // Toyota Land Cruiser
        expect(year('KNDPM3AC5K7523456'), '2019'); // Kia Sportage
        expect(year('LGWEF6A55MH012345'), '2021'); // Haval H6
        expect(year('HJRPBGJB1NB123456'), '2022'); // ISO 3780 H = China
      });

      test('Mercedes ECE (pos 10 = drive side) → Unknown, not 2001', () {
        expect(year('WDD2050431F123456'), 'Unknown'); // C 200, '1' = LHD
        expect(year('WDB9066331S123456'), 'Unknown'); // Sprinter
        expect(year('W1K2060421R123456'), 'Unknown');
        expect(year('W1V9076331P123456'), 'Unknown');
      });

      test('Renault / Dacia / PSA / Fiat / Ford Europe / BMW Europe → Unknown',
          () {
        expect(year('UU1LSDAAH43612345'), 'Unknown'); // Dacia, not 2004
        expect(year('VF1MA000864512345'), 'Unknown');
        expect(year('VF3LCYHZPHS123456'), 'Unknown');
        expect(year('ZFA31200000123456'), 'Unknown');
        expect(year('WF0DXXGAKD8E12345'), 'Unknown');
        expect(year('WBA3A5C51CF256551'), 'Unknown');
        expect(year('WMWZC31090T123456'), 'Unknown'); // MINI
      });

      test('makers that encode position 10 in all markets are decoded', () {
        expect(year('WVWZZZAUZJW123456'), '2018'); // VW Golf
        expect(year('WVGZZZ5NZJW123456'), '2018'); // VW Tiguan
        expect(year('WAUZZZ4GZCN123456'), '2012'); // Audi A6
        expect(year('WP0ZZZ99ZGS123456'), '2016'); // Porsche 911
        expect(year('TMBJJ7NE8J0123456'), '2018'); // Škoda
        expect(year('VSSZZZ6JZ9R123456'), '2009'); // SEAT
        expect(year('YV1MS382062123456'), '2006'); // Volvo
        expect(year('YS3FD49Y581123456'), '2008'); // Saab
        expect(year('SALGA2EF7GA123456'), '2016'); // Range Rover
        expect(year('SAJAA4BN0HA123456'), '2017'); // Jaguar
        expect(year('MR0HA3CD3K0123456'), '2019'); // Toyota Thailand
      });

      test('Mazda Europe export (JMZ) → Unknown despite region J', () {
        expect(year('JMZGG14F6A1123456'), 'Unknown');
      });

      test('other regions without a known encoding → Unknown', () {
        expect(year('NMTBZ3BE4L1123456'), 'Unknown'); // Toyota Turkey
        expect(year('MA3EWDE1SL0123456'), 'Unknown'); // India
      });
    });
  });

  // ── Manufacturer (WMI) ─────────────────────────────────────────────────────

  group('decode — manufacturer WMIs', () {
    const wmis = {
      // Korean
      'KM8': 'Hyundai', 'KMJ': 'Hyundai', 'KND': 'Kia',
      // Chinese
      'LS5': 'Changan', 'LSJ': 'SAIC MG', 'L6T': 'Geely', 'LVV': 'Chery',
      'LGW': 'Great Wall Motor (GWM)',
      // Japanese / Asian plants
      'JTM': 'Toyota', 'JTE': 'Toyota', 'JTN': 'Toyota', 'JTH': 'Lexus',
      'MR0': 'Toyota', 'JMY': 'Mitsubishi', 'JA4': 'Mitsubishi',
      'JHL': 'Honda', 'JMZ': 'Mazda',
      // American
      '1GN': 'Chevrolet', '1GK': 'GMC', '1GY': 'Cadillac', '1GT': 'GMC',
      '1C4': 'Chrysler/Jeep/Dodge', '1C3': 'Chrysler/Dodge',
      '1J4': 'Jeep', '1J8': 'Jeep',
      '1C6': 'Ram', '3C6': 'Ram', '3D7': 'Dodge',
      '3GC': 'Chevrolet', '3GN': 'Chevrolet',
      '2GC': 'Chevrolet', '2GT': 'GMC',
      // European
      '5UX': 'BMW', '4US': 'BMW', 'W1K': 'Mercedes', 'W1N': 'Mercedes',
      'W1V': 'Mercedes', 'WMW': 'MINI', 'TMB': 'Škoda', 'VSS': 'SEAT',
      'WF0': 'Ford', 'ZFA': 'Fiat', 'WVG': 'Volkswagen', 'WA1': 'Audi',
      'SAD': 'Jaguar', 'SCF': 'Aston Martin',
    };
    for (final MapEntry(key: wmi, value: make) in wmis.entries) {
      test('$wmi → $make', () {
        expect(VinDecoder.decode('${wmi}AA11B1NA000001')['manufacturer'],
            make);
      });
    }

    test('1GT is GMC (trucks), not Chevrolet', () {
      expect(VinDecoder.decode('1GTU9FEL0LZ100001')['manufacturer'], 'GMC');
    });

    test('corrected legacy entries: WAP = Alpina, SDB = Talbot', () {
      expect(VinDecoder.decode('WAPAA11B1NA000001')['manufacturer'], 'Alpina');
      expect(VinDecoder.decode('SDBAA11B1NA000001')['manufacturer'], 'Talbot');
    });

    test('JHG is not mapped (no authoritative assignment found)', () {
      expect(VinDecoder.decode('JHGAA11B1NA000001')['manufacturer'],
          'Unknown');
    });
  });

  // ── Country (ISO 3780) ─────────────────────────────────────────────────────

  group('decode — ISO 3780 country ranges', () {
    String country(String wmi) =>
        VinDecoder.decode('${wmi}AA11B1NA000001')['country']!;

    test('M region: India / Indonesia / Thailand, not "India" for all', () {
      expect(country('MAJ'), 'India'); // MA–ME
      expect(country('MEE'), 'India');
      expect(country('MFA'), 'Indonesia'); // MF–MK
      expect(country('MHF'), 'Indonesia');
      expect(country('MKA'), 'Indonesia');
      expect(country('MLA'), 'Thailand'); // ML–MR
      expect(country('MR0'), 'Thailand'); // Toyota Hilux, Thailand
      expect(country('MSA'), 'Myanmar');
      expect(country('MUA'), 'Mongolia');
      expect(country('MXA'), 'Kazakhstan');
      expect(country('MZA'), 'India'); // MY–M0
      expect(country('MTA'), 'Unknown'); // unassigned
    });

    test('other split Asian regions', () {
      expect(country('KFA'), 'Israel');
      expect(country('KNA'), 'South Korea');
      expect(country('KSA'), 'Jordan');
      expect(country('K1A'), 'South Korea');
      expect(country('K5A'), 'Kyrgyzstan');
      expect(country('NAA'), 'Iran');
      expect(country('NFA'), 'Pakistan');
      expect(country('NJA'), 'Iraq');
      expect(country('NMT'), 'Turkey');
      expect(country('NSA'), 'Uzbekistan');
      expect(country('N3A'), 'Iran');
      expect(country('N7A'), 'Turkey');
      expect(country('PAA'), 'Philippines');
      expect(country('PFA'), 'Singapore');
      expect(country('PLA'), 'Malaysia');
      expect(country('PSA'), 'Bangladesh');
      expect(country('P6A'), 'India');
      expect(country('RAA'), 'United Arab Emirates');
      expect(country('RFA'), 'Taiwan');
      expect(country('RLA'), 'Vietnam');
      expect(country('RPA'), 'Laos');
      expect(country('RSA'), 'Saudi Arabia');
      expect(country('R2A'), 'Hong Kong');
      expect(country('HJR'), 'China'); // H row is China (2021 chart)
      expect(country('LGW'), 'China');
    });

    test('Africa is split by the second character', () {
      expect(country('AAA'), 'South Africa');
      expect(country('AJA'), 'Ivory Coast');
      expect(country('A1A'), 'Cyprus');
      expect(country('BAA'), 'Angola');
      expect(country('BFA'), 'Kenya');
      expect(country('CAA'), 'Egypt');
      expect(country('CFA'), 'Morocco');
      expect(country('CCA'), 'Unknown');
    });

    test('remaining European splits', () {
      expect(country('S3A'), 'Georgia');
      expect(country('S4A'), 'Iceland');
      expect(country('T6A'), 'Andorra');
      expect(country('T7A'), 'Netherlands');
      expect(country('UAA'), 'Spain');
      expect(country('U1A'), 'North Macedonia');
      expect(country('U9A'), 'Bosnia and Herzegovina');
      expect(country('XDA'), 'Russia');
      expect(country('XJA'), 'Russia');
      expect(country('X7L'), 'Russia'); // Renault Russia
      expect(country('X96'), 'Russia');
      expect(country('YNA'), 'Malta');
      expect(country('ZFA'), 'Italy');
      expect(country('ZXA'), 'Slovenia');
      expect(country('Z1A'), 'San Marino');
      expect(country('Z3A'), 'Lithuania');
      expect(country('Z7A'), 'Russia');
      expect(country('ERA'), 'Russia'); // E row is Russia
    });

    test('North America, Oceania, South America', () {
      expect(country('3C6'), 'Mexico');
      expect(country('34A'), 'Nicaragua');
      expect(country('38A'), 'Puerto Rico');
      expect(country('7SA'), 'United States');
      expect(country('6FP'), 'Australia');
      expect(country('6ZA'), 'New Zealand');
      expect(country('8AP'), 'Argentina');
      expect(country('8FA'), 'Chile');
      expect(country('8SA'), 'Peru');
      expect(country('9BW'), 'Brazil');
      expect(country('93H'), 'Brazil');
      expect(country('9FA'), 'Colombia');
      expect(country('9SA'), 'Uruguay');
    });

    test('unassigned rows D, F, G → Unknown', () {
      expect(country('DAA'), 'Unknown');
      expect(country('FAA'), 'Unknown');
      expect(country('GAA'), 'Unknown');
    });
  });

  // ── Invalid input ──────────────────────────────────────────────────────────

  group('decode — invalid input', () {
    test('empty string returns an error and echoes the input', () {
      final r = VinDecoder.decode('');
      expect(r['error'], 'Incomplete VIN');
      expect(r['vin'], '');
      expect(r.containsKey('manufacturer'), isFalse);
    });

    test('16-char VIN (one short) is rejected, not partially decoded', () {
      final short = _taurus2019.substring(0, 16);
      final r = VinDecoder.decode(short);
      expect(r['error'], 'Incomplete VIN');
      expect(r['vin'], short);
      expect(r.containsKey('year'), isFalse);
    });

    test('pre-1981 style short VIN (11 chars) is rejected', () {
      expect(VinDecoder.decode('1F02H123456')['error'], 'Incomplete VIN');
    });

    test('exactly 17 chars is accepted', () {
      expect(VinDecoder.decode(_taurus2019).containsKey('error'), isFalse);
    });

    test('more than 17 chars is rejected (VIN is exactly 17 per ISO 3779)',
        () {
      final r = VinDecoder.decode('${_taurus2019}9');
      expect(r.containsKey('error'), isTrue);
      expect(r['vin'], '${_taurus2019}9');
      expect(r.containsKey('serial'), isFalse);
    });
  });

  // ── Chinese-brand WMIs (Wikibooks WMI list; see vin_decoder.dart) ─────────

  group('decode — Chinese-brand WMIs', () {
    final now = DateTime(2026, 11, 7);

    // (WMI, exact maker, country). Country/year use a VIN template whose
    // position 10 is 'N' (2022).
    const wmis = [
      // Changan group
      ('LS4', 'Changan', 'China'),
      ('LS6', 'Changan (Deepal/Avatr)', 'China'),
      ('LSC', 'Changan', 'China'),
      ('LVR', 'Mazda (Changan)', 'China'),
      // JMC / JMC-Ford
      ('LEF', 'JMC', 'China'),
      ('LJX', 'Ford (JMC)', 'China'),
      ('LXW', 'Ford (JMC)', 'China'),
      // Chery group
      ('LVT', 'Chery (Exeed/Jetour)', 'China'),
      ('LVU', 'Chery (Jetour/Omoda/Jaecoo)', 'China'),
      ('LNN', 'Chery (Omoda/Jaecoo)', 'China'),
      ('HJR', 'Jetour (Chery)', 'China'),
      ('LVM', 'Chery Commercial', 'China'),
      ('L2C', 'Chery Jaguar Land Rover', 'China'),
      // GWM
      ('LGW', 'Great Wall Motor (GWM)', 'China'),
      ('MNU', 'Great Wall Motor (GWM)', 'Thailand'),
      ('XZG', 'Haval (Great Wall Motor)', 'Russia'),
      // BAIC, JAC, FAW
      ('LNB', 'BAIC', 'China'),
      ('LJ1', 'JAC / Nio', 'China'),
      ('LFP', 'FAW (Hongqi/Bestune)', 'China'),
      ('LFB', 'FAW', 'China'),
      // Dongfeng
      ('LDP', 'Dongfeng (Aeolus/Voyah)', 'China'),
      ('LGJ', 'Dongfeng (Aeolus)', 'China'),
      ('LGG', 'Dongfeng (Forthing)', 'China'),
      ('LMX', 'Dongfeng (Forthing)', 'China'),
      // BYD, GAC Aion, Geely, Proton
      ('LC0', 'BYD', 'China'),
      ('LGX', 'BYD', 'China'),
      ('LPE', 'BYD', 'China'),
      ('LNA', 'GAC Aion', 'China'),
      ('L10', 'Geely', 'China'),
      ('PL1', 'Proton', 'Malaysia'),
    ];
    for (final (wmi, make, country) in wmis) {
      test('$wmi → $make / $country', () {
        final d = VinDecoder.decode('${wmi}AA11B1NA000001', now: now);
        expect(d['manufacturer'], make);
        expect(d['country'], country);
      });
    }

    test('LGW is labelled as GWM (Haval, Tank, Wey, Ora, Poer), not Haval',
        () {
      final m = VinDecoder.decode('LGWEF6A55MH012345')['manufacturer'];
      expect(m, 'Great Wall Motor (GWM)');
      expect(m, isNot(contains('Haval')));
    });

    test('China (L, H): model year decoded per GB 16735', () {
      for (final (wmi, _, country) in wmis) {
        if (country != 'China') continue;
        expect(VinDecoder.decode('${wmi}AA11B1NA000001', now: now)['year'],
            '2022', reason: wmi);
      }
    });

    test('GWM Thailand (MNU), Haval Russia (XZG), Proton (PL1): year Unknown',
        () {
      // Built outside China, so GB 16735 does not apply, and their regions
      // have no model-year rule for position 10.
      for (final wmi in ['MNU', 'XZG', 'PL1']) {
        expect(VinDecoder.decode('${wmi}AA11B1NA000001', now: now)['year'],
            VinDecoder.unknown, reason: wmi);
      }
    });
  });

  // ── getVin(): position-9 check digit (ProductionOBDAdapter._isValidVin) ───

  group('getVin() — check digit by region', () {
    SimCar car(String vin) => SimCar(
      protocol: '6',
      responses: {
        '0100': '41 00 BE 1F B8 10',
        '0902': _vinFrames(vin).join('\n'),
      },
    );
    String? readVin(String vin) {
      String? out;
      sim(car(vin), (rig) => out = rig.drive(rig.adapter.getVin()));
      return out;
    }

    test('China (L): correct GB 16735 check digit → VIN accepted', () {
      const vin = 'LS4ASB3R7MA012345'; // Changan CS35 Plus
      expect(_checkDigit(vin), vin[8]);
      expect(readVin(vin), vin);
    });

    test('China (L): one garbled serial digit → check digit fails → null',
        () {
      const garbled = 'LS4ASB3R7MA012346'; // last digit 5 → 6
      expect(_checkDigit(garbled), isNot(garbled[8]));
      expect(readVin(garbled), isNull);
    });

    test('China (H row, 2021 ISO 3780 chart): checked too', () {
      const real = 'HJRPBGFB9RF149510'; // Jetour X70 Plus listing VIN
      expect(_checkDigit(real), real[8]);
      expect(readVin(real), real);
      expect(readVin('HJRPBGFB9RF149511'), isNull);
    });

    test('Korea (K): not checked — domestic VINs use position 9 for a '
        'market / drive-side letter', () {
      const domestic = 'KMHD341DPBU123456'; // 'P' at position 9
      expect(_checkDigit(domestic), isNot(domestic[8]));
      expect(readVin(domestic), domestic);
    });

    test('Europe (W), Thailand (M), Malaysia (P): not checked', () {
      for (final vin in [
        'WVWZZZ1KZ8W123456',
        'MNUFF7A60NE012345',
        'PL1BT6KN0MB012345',
      ]) {
        expect(readVin(vin), vin, reason: vin);
      }
    });

    test('North America (1-5): still checked', () {
      expect(readVin('1HGCM82633A004352'), '1HGCM82633A004352');
      expect(readVin('1HGCM82603A004352'), isNull);
    });
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

const _translit = {
  'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5, 'F': 6, 'G': 7, 'H': 8, //
  'J': 1, 'K': 2, 'L': 3, 'M': 4, 'N': 5, 'P': 7, 'R': 9,
  'S': 2, 'T': 3, 'U': 4, 'V': 5, 'W': 6, 'X': 7, 'Y': 8, 'Z': 9,
};
const _weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];

/// ISO 3779 / 49 CFR 565 / GB 16735 position-9 check digit of [vin].
String _checkDigit(String vin) {
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += (int.tryParse(vin[i]) ?? _translit[vin[i]]!) * _weights[i];
  }
  final r = sum % 11;
  return r == 10 ? 'X' : '$r';
}

String _hexOf(Iterable<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

/// [vin] as the four lines of a CAN ISO-TP 0902 reply (headers off).
List<String> _vinFrames(String vin) {
  final p = [0x49, 0x02, 0x01, ...vin.codeUnits];
  return [
    '014',
    '0: ${_hexOf(p.sublist(0, 6))}',
    '1: ${_hexOf(p.sublist(6, 13))}',
    '2: ${_hexOf(p.sublist(13, 20))}',
  ];
}
