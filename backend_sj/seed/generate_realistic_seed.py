"""Realistic GSO inventory for San Jose: writes realistic_seed.sql next to this file.

Run:  python generate_realistic_seed.py
Then: mysql ... < realistic_seed.sql   and restart the backend (it signs the new assets' QR codes).

The SQL deletes ALL asset data (assets, history, maintenance, disposal, transfers, return slips,
PARs, photos records, AI results, asset-related audit entries), keeps accounts / offices /
categories / articles, adds staff accounts as accountable persons, and inserts about 2,000
assets acquired 2015 to today with their history: issue on a PAR, transfers with a Property
Return Slip and new PAR, repairs with parts and labor, and disposals. Offices, categories,
articles and users are looked up by name, so the same file runs on any copy of the database.
The output is the same on every run (fixed random seed).
"""
import datetime as dt
import os
import random
import string

R = random.Random(20261029)
TODAY = dt.date(2026, 10, 29)
START_YEAR = 2015
HERE = os.path.dirname(os.path.abspath(__file__))


def q(v):
    if v is None:
        return 'NULL'
    if isinstance(v, bool):
        return '1' if v else '0'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, dt.datetime):
        return "'" + v.strftime('%Y-%m-%d %H:%M:%S') + "'"
    if isinstance(v, dt.date):
        return "'" + v.isoformat() + "'"
    return "'" + str(v).replace('\\', '\\\\').replace("'", "''") + "'"


def at(day, h0=8, h1=16):
    """A working-hours time on that day (stored as UTC: Manila minus 8 hours)."""
    local = dt.datetime.combine(day, dt.time(R.randint(h0, h1), R.randint(0, 59), R.randint(0, 59)))
    return local - dt.timedelta(hours=8)


def workday(d):
    while d.weekday() >= 5:
        d += dt.timedelta(days=1)
    return d


def rand_date(a, b):
    if b <= a:
        return a
    return workday(a + dt.timedelta(days=R.randint(0, (b - a).days)))


def peso(lo, hi, step=50):
    return round(R.randint(lo // step, hi // step) * step + R.choice([0, 0, 0, 0.5 * step if step >= 100 else 0]), 2)


def serial_no(prefix='', n=10, letters=True):
    pool = (string.ascii_uppercase + string.digits) if letters else string.digits
    return prefix + ''.join(R.choice(pool) for _ in range(n))


# ── Offices: code, building / floor, staff (name, position) ──────────────────────────────
FIRST_M = ['Juan', 'Jose', 'Mark', 'John Paul', 'Ramon', 'Ernesto', 'Rodolfo', 'Antonio', 'Eduardo', 'Rogelio',
           'Danilo', 'Arnel', 'Jerome', 'Christian', 'Romeo', 'Noel', 'Ronaldo', 'Alvin', 'Ferdinand', 'Reynaldo',
           'Jayson', 'Kenneth', 'Ariel', 'Rommel', 'Joel', 'Marvin', 'Renato', 'Elmer', 'Wilfredo', 'Dennis']
FIRST_F = ['Maria', 'Ana', 'Rosario', 'Teresita', 'Liza', 'Cristina', 'Josephine', 'Marites', 'Elena', 'Gloria',
           'Rowena', 'Imelda', 'Melanie', 'Jocelyn', 'Ma. Theresa', 'Lorna', 'Evelyn', 'Divina', 'Shiela', 'Arlene',
           'Kristine', 'Angelica', 'Mylene', 'Rachelle', 'Jennifer', 'Leah', 'Charmaine', 'Grace', 'Analyn', 'Rhea']
SURNAMES = ['Dela Cruz', 'Santos', 'Reyes', 'Garcia', 'Mendoza', 'Torres', 'Villanueva', 'Ramos', 'Aquino', 'Castillo',
            'Bautista', 'Navarro', 'Fernandez', 'Lopez', 'Gonzales', 'Rivera', 'Domingo', 'Pascual', 'Salazar', 'Mercado',
            'Soriano', 'Valdez', 'Aguilar', 'Manalo', 'Cruz', 'De Guzman', 'Tolentino', 'Ocampo', 'Panganiban', 'Lacson',
            'Manalang', 'Esguerra', 'Dizon', 'Samonte', 'Carpio', 'Magbanua', 'Robles', 'Velasco', 'Ignacio', 'Sison',
            'Buenaventura', 'Evangelista', 'Galang', 'Quiambao', 'Macaraeg', 'Tan', 'Lim', 'Yap', 'Abrenica', 'Baluyot']
used_names = set()


def person():
    while True:
        female = R.random() < 0.55
        first = R.choice(FIRST_F if female else FIRST_M)
        last = R.choice(SURNAMES)
        mid = R.choice(string.ascii_uppercase.replace('Q', '').replace('X', ''))
        name = f'{first} {mid}. {last}'
        if name not in used_names:
            used_names.add(name)
            return name


# office name -> (building/floor, [positions: head first, then the rest]), size factor
OFFICES = {
    'Office of the Mayor': ('Municipal Hall, 2nd Floor', ['Municipal Mayor', 'Executive Assistant III', 'Administrative Officer IV', 'Administrative Aide IV'], 1.3),
    'Office of the Vice Mayor': ('Legislative Building, 2nd Floor', ['Municipal Vice Mayor', 'Administrative Assistant II'], 0.6),
    'Sangguniang Bayan Office': ('Legislative Building, Session Hall', ['Secretary to the Sangguniang Bayan', 'Administrative Officer II', 'Administrative Aide III'], 1.0),
    'Human Resource Management Office': ('Municipal Hall, Ground Floor', ['MGDH I (HRMO)', 'Administrative Officer III'], 0.8),
    'Municipal Planning and Development Office': ('Municipal Hall, 3rd Floor', ['MGDH I (MPDC)', 'Planning Officer II', 'Draftsman II'], 0.9),
    "Civil Registrar's Office": ('Municipal Hall, Ground Floor', ['Municipal Civil Registrar', 'Registration Officer I', 'Administrative Aide IV'], 0.9),
    'General Services Office': ('GSO Building and Warehouse', ['MGDH I (GSO)', 'Supply Officer II', 'Administrative Aide IV'], 1.0),
    'Budget Office': ('Municipal Hall, 2nd Floor', ['MGDH I (Budget Officer)', 'Administrative Officer II'], 0.7),
    'Accounting Office': ('Municipal Hall, 2nd Floor', ['Municipal Accountant', 'Administrative Officer IV', 'Bookkeeper'], 0.9),
    'Treasury Office': ('Municipal Hall, Ground Floor', ['Municipal Treasurer', 'Revenue Collection Clerk III', 'Cashier II', 'Local Revenue Collection Officer I'], 1.2),
    "Assessor's Office": ('Municipal Hall, Ground Floor', ['Municipal Assessor', 'Assessment Clerk III', 'Tax Mapper II'], 1.0),
    'Information and Communications Technology Office': ('Municipal Hall, 3rd Floor', ['ICT Officer II', 'Computer Programmer I', 'Computer Maintenance Technologist I'], 0.9),
    'Municipal Health Office': ('Rural Health Unit', ['Municipal Health Officer', 'Nurse II', 'Midwife II', 'Medical Technologist I', 'Sanitation Inspector I'], 1.3),
    'Municipal Social Welfare and Development Office': ('MSWD Building', ['MSWDO', 'Social Welfare Officer II', 'Day Care Worker I'], 1.0),
    'Municipal Agriculture Office': ('Agriculture Building', ['Municipal Agriculturist', 'Agricultural Technologist', 'Agricultural Technologist'], 1.0),
    'Municipal Engineering Office': ('Engineering Building', ['Municipal Engineer', 'Engineer II', 'Engineering Assistant', 'Heavy Equipment Operator II', 'Driver II'], 1.4),
    'Disaster Risk Reduction and Management Office': ('MDRRM Operations Center', ['MDRRMO', 'LDRRM Assistant', 'Emergency Responder', 'Driver I'], 1.1),
}
ROOMS = {
    'Office of the Mayor': ["Mayor's Office", 'Executive Staff Room', 'Conference Room'],
    'Sangguniang Bayan Office': ['Session Hall', 'SB Secretariat'],
    'Municipal Health Office': ['Consultation Room', 'Laboratory', 'Treatment Room', 'Records Section'],
    'Treasury Office': ['Collection Window', 'Cashier', 'Records Section'],
    'Municipal Engineering Office': ['Engineering Office', 'Motor Pool', 'Equipment Yard'],
    'Disaster Risk Reduction and Management Office': ['Operations Center', 'Equipment Room', 'Rescue Bay'],
    'General Services Office': ['Supply Section', 'Warehouse', 'Motor Pool'],
    'Municipal Agriculture Office': ['Agriculture Office', 'Equipment Shed'],
}

# ── What gets bought: article -> list of (description, from year, to year, price lo, hi, specs, serial prefix) ──
CAT = {
    'ICT Equipment': {
        'Desktop Computer': [
            ('Acer Veriton M2640G Desktop Computer Set', 2015, 2018, 32000, 38000, 'Intel Core i5-6400, 8GB DDR4, 1TB HDD, 19.5" LED monitor, keyboard and mouse, Windows 10 Pro', 'DTVP'),
            ('Lenovo ThinkCentre M720t Desktop Computer Set', 2018, 2021, 38000, 45000, 'Intel Core i5-8400, 8GB DDR4, 1TB HDD, 21.5" LED monitor, Windows 10 Pro', 'PC1'),
            ('HP ProDesk 400 G7 Desktop Computer Set', 2020, 2023, 42000, 52000, 'Intel Core i5-10500, 8GB DDR4, 512GB SSD, 21.5" LED monitor, Windows 11 Pro', '4CE'),
            ('Dell OptiPlex 7010 Tower Desktop Computer Set', 2023, 2026, 48000, 58000, 'Intel Core i5-13500, 16GB DDR4, 512GB NVMe SSD, 23.8" IPS monitor, Windows 11 Pro', 'D7'),
        ],
        'Laptop': [
            ('Acer TravelMate P249 Laptop', 2015, 2018, 38000, 45000, 'Intel Core i5-6200U, 8GB RAM, 500GB HDD, 14" HD, Windows 10 Pro', 'NXV'),
            ('Lenovo ThinkPad E14 Laptop', 2019, 2022, 48000, 58000, 'Intel Core i5-10210U, 8GB RAM, 256GB SSD, 14" FHD, Windows 10 Pro', 'PF2'),
            ('Dell Latitude 5440 Laptop', 2023, 2026, 62000, 75000, 'Intel Core i5-1345U, 16GB RAM, 512GB SSD, 14" FHD, Windows 11 Pro', 'D54'),
        ],
        'Monitor': [
            ('Samsung 24" LED Monitor', 2016, 2021, 6500, 8500, '24" FHD 1920x1080, HDMI/VGA', 'ZZA'),
            ('Dell P2422H 24" IPS Monitor', 2021, 2026, 9500, 12500, '23.8" FHD IPS, HDMI/DisplayPort', 'CN0'),
        ],
        'Printer': [
            ('Epson L360 Ink Tank Printer', 2015, 2019, 8500, 9800, 'Print/scan/copy, ink tank, USB', 'VGF'),
            ('Epson L3210 Ink Tank Printer', 2020, 2026, 9800, 11500, 'Print/scan/copy, ink tank, USB', 'X8G'),
            ('Brother HL-L5100DN Laser Printer', 2017, 2022, 18500, 24000, 'Monochrome laser, 40ppm, duplex, network', 'E7'),
            ('HP LaserJet Pro M404dn Printer', 2021, 2026, 24000, 29500, 'Monochrome laser, 38ppm, duplex, Ethernet', 'PHB'),
            ('Epson LQ-310 Dot Matrix Printer', 2015, 2024, 11500, 14500, '24-pin dot matrix, for receipts and forms', 'Q4Y'),
        ],
        'Scanner': [('Canon imageFORMULA DR-C225 II Document Scanner', 2017, 2026, 22000, 32000, '25ppm duplex, 30-sheet ADF', 'GE1')],
        'Projector': [
            ('Epson EB-X41 LCD Projector', 2016, 2020, 26000, 32000, '3,600 lumens, XGA, HDMI', 'X4K'),
            ('Epson EB-X49 LCD Projector', 2021, 2026, 32000, 39000, '3,600 lumens, XGA, HDMI, with screen', 'X5L'),
        ],
        'Network Switch': [('TP-Link TL-SG1024D 24-Port Gigabit Switch', 2016, 2026, 6500, 9800, '24 x 10/100/1000 ports, rack-mountable', '22'),
                           ('Cisco CBS250-24T-4G Managed Switch', 2022, 2026, 28000, 38000, '24 x Gigabit, 4 x SFP, managed', 'PSZ')],
        'Router': [('MikroTik hEX RB750Gr3 Router', 2018, 2026, 4200, 5500, '5 x Gigabit, RouterOS L4', 'HC'),
                   ('TP-Link Archer C6 Wireless Router', 2019, 2026, 2900, 3800, 'AC1200 dual band', '21')],
        'UPS': [('APC Back-UPS BX650LI-MS 650VA', 2015, 2026, 3400, 4600, '650VA/325W, 4 outlets, AVR', '3B1'),
                ('APC Smart-UPS SMT1500I 1500VA', 2018, 2026, 32000, 42000, '1500VA/1000W, LCD, for servers and network', 'AS1')],
        'External Hard Drive': [('Seagate Expansion 2TB External Hard Drive', 2017, 2026, 3600, 4800, '2TB USB 3.0', 'NA'),
                                ('WD My Passport 4TB External Hard Drive', 2021, 2026, 6200, 7800, '4TB USB 3.2, hardware encryption', 'WX')],
        'Tablet': [('Samsung Galaxy Tab A8 10.5"', 2022, 2026, 14500, 17500, '4GB/64GB, Wi-Fi + LTE, for field data gathering', 'R9')],
    },
    'Office Furniture': {
        'Office Desk': [('Executive Office Desk with Side Return (L-type)', 2015, 2026, 14500, 24500, 'Wood laminate, 160 x 80 cm, with mobile pedestal', None),
                        ('Clerical Table, Steel Frame', 2015, 2026, 6500, 9500, '120 x 60 cm, 2 drawers', None)],
        'Office Chair': [('Executive Swivel Chair, High Back', 2015, 2026, 6500, 9800, 'Mesh back, gas lift, armrest', None),
                         ('Clerical Swivel Chair', 2015, 2026, 3800, 5200, 'Fabric, gas lift, armless', None)],
        "Visitor's Chair": [("Visitor's Chair, Stackable", 2015, 2026, 1800, 2800, 'Steel frame, padded seat', None),
                            ('Monobloc Chair with Armrest', 2015, 2026, 450, 650, 'Heavy-duty plastic', None)],
        'Filing Cabinet': [('Steel Filing Cabinet, 4-Drawer', 2015, 2026, 9500, 14500, 'Gauge 22 steel, with lock, legal size', None)],
        'Steel Locker': [('Steel Locker, 6-Door', 2015, 2026, 9800, 13500, 'Gauge 24 steel, with individual locks', None)],
        'Bookshelf': [('Steel Open Shelf, 5-Layer', 2015, 2026, 5500, 8500, '90 x 45 x 200 cm', None)],
        'Conference Table': [('Conference Table, 10-Seater', 2016, 2026, 32000, 48000, 'Wood laminate, 300 x 120 cm', None)],
        'Partition Panel': [('Office Partition Panel', 2017, 2026, 8500, 14500, 'Fabric-covered, aluminum frame, 120 x 150 cm', None)],
    },
    'Office Equipment': {
        'Photocopier': [('Canon imageRUNNER 2525 Photocopier', 2015, 2019, 95000, 120000, 'Mono 25cpm, A3, duplex, network print/scan', 'RXF'),
                        ('Canon imageRUNNER 2625i Photocopier', 2020, 2026, 125000, 158000, 'Mono 25cpm, A3, duplex, network print/scan, 7" touch panel', 'QLZ')],
        'Binding Machine': [('Ring Binding Machine (Comb)', 2015, 2026, 7500, 12500, 'A4, 21-hole, 450 sheets', None)],
        'Laminating Machine': [('Laminating Machine A3', 2015, 2026, 4500, 7800, 'A3, 2-roller, 125 micron', None)],
        'Paper Shredder': [('Heavy-Duty Paper Shredder', 2016, 2026, 12500, 22000, 'Cross-cut, 20 sheets, 30L bin', None)],
        'Typewriter': [('Olympia SM Manual Typewriter', 2015, 2016, 12500, 15500, 'Long carriage, for official forms', None)],
        'Fax Machine': [('Panasonic KX-FT983 Fax Machine', 2015, 2017, 7800, 9500, 'Thermal fax, telephone and answering machine', 'KX')],
        'Calculator': [('Casio DR-120R Printing Calculator', 2015, 2026, 3200, 4500, '12-digit, two-color printing', None)],
        'Cash Counting Machine': [('Glory GFB-800 Bill Counter with Counterfeit Detection', 2018, 2026, 24000, 32000, 'UV/MG/IR detection, batch counting', 'GF')],
        'Bulletin Board': [('Bulletin Board, Cork with Glass Cover', 2015, 2026, 3500, 6500, '120 x 90 cm, aluminum frame, lockable', None)],
    },
    'Appliances': {
        'Air Conditioner': [('Carrier 1.5HP Window-Type Air Conditioner', 2015, 2018, 22000, 26000, '1.5HP, 12,000 kJ/h, non-inverter', 'CAR'),
                            ('Panasonic 1.5HP Inverter Split-Type Air Conditioner', 2019, 2026, 38000, 46000, '1.5HP inverter, R32, wall-mounted', 'PAN'),
                            ('Daikin 2.0HP Inverter Split-Type Air Conditioner', 2020, 2026, 52000, 62000, '2.0HP inverter, R32, wall-mounted', 'DKN')],
        'Electric Fan': [('Standard 16" Stand Fan', 2015, 2026, 1600, 2400, '16", 3-speed', None),
                         ('Asahi 18" Industrial Wall Fan', 2017, 2026, 3200, 4500, '18", 3-speed, metal blades', None)],
        'Refrigerator': [('Samsung 7.4 cu.ft. Two-Door Refrigerator', 2017, 2026, 22000, 28500, 'No-frost, digital inverter', 'SRF'),
                         ('Vaccine Refrigerator (Solar Direct Drive)', 2019, 2026, 185000, 245000, 'WHO PQS certified, 60L vaccine storage', 'VR')],
        'Microwave Oven': [('Sharp 20L Microwave Oven', 2016, 2026, 4800, 6500, '20L, 800W', None)],
        'Water Dispenser': [('Hot and Cold Water Dispenser, Bottom Load', 2016, 2026, 8500, 12500, 'Stainless tank, child lock', None)],
        'Electric Kettle': [('Electric Kettle 1.7L', 2016, 2026, 950, 1600, 'Stainless steel, auto shut-off', None)],
        'Vacuum Cleaner': [('Wet and Dry Vacuum Cleaner 20L', 2017, 2026, 6500, 9500, '1,200W, 20L tank', None)],
        'Television': [('Samsung 55" 4K UHD Smart TV', 2019, 2026, 32000, 42000, '55" Crystal UHD, for presentations and IEC', 'TV5')],
    },
    'Motor Vehicle': {
        'Ambulance': [('Toyota Hiace Commuter Ambulance Conversion', 2016, 2026, 2950000, 3650000, '3.0L diesel, Type I ambulance, stretcher, oxygen, siren and lights', 'JTF')],
        'Van': [('Toyota Hiace Commuter 15-Seater Van', 2015, 2026, 1750000, 2150000, '3.0L diesel, manual, 15 seats', 'JTF'),
                ('Nissan NV350 Urvan 15-Seater', 2018, 2023, 1550000, 1850000, '2.5L diesel, manual', 'JN1')],
        'Pick-up Truck': [('Toyota Hilux 2.4 J 4x2 Pick-up', 2016, 2026, 1180000, 1450000, '2.4L diesel, manual, single cab', 'MR0'),
                          ('Mitsubishi Strada GL 4x2 Pick-up', 2018, 2024, 1050000, 1250000, '2.4L diesel, manual, double cab', 'MMB')],
        'Dump Truck': [('Isuzu Giga FVR 6-Wheeler Dump Truck', 2015, 2026, 3650000, 4850000, '7.8L diesel, 6 cu.m. dump body', 'JAL')],
        'Sedan': [('Toyota Vios 1.3 XLE Sedan', 2016, 2025, 780000, 920000, '1.3L gasoline, CVT', 'MHF')],
        'Motorcycle': [('Honda XRM 125 Motorcycle', 2015, 2026, 68000, 82000, '125cc, for field personnel', 'KF'),
                       ('Yamaha Sniper 155 Motorcycle', 2020, 2026, 118000, 130000, '155cc', 'G3')],
        'Utility Vehicle': [('Toyota Innova 2.8 E Diesel', 2017, 2026, 1450000, 1680000, '2.8L diesel, 7 seats', 'MHF'),
                            ('Mitsubishi Montero Sport GLX 4x2', 2019, 2026, 1650000, 1880000, '2.4L diesel, 7 seats', 'MMA')],
    },
    'Heavy Equipment': {
        'Backhoe Loader': [('JCB 3DX Backhoe Loader', 2016, 2026, 4850000, 6200000, '76hp, 1.0 cu.m. loader bucket', 'JCB')],
        'Bulldozer': [('Komatsu D31EX Crawler Dozer', 2017, 2024, 8500000, 10500000, '79hp, straight tilt blade', 'KMT')],
        'Road Roller': [('Sakai SV512 Vibratory Road Roller', 2018, 2026, 4200000, 5600000, '10-ton, smooth drum', 'SKA')],
        'Concrete Mixer': [('One-Bagger Concrete Mixer', 2015, 2026, 95000, 145000, '1-bagger, 7hp gasoline engine', None)],
        'Generator Set': [('Denyo 25kVA Diesel Generator Set', 2016, 2026, 650000, 850000, '25kVA, silent type, automatic transfer switch', 'DCA'),
                          ('Honda EP6500CX 5.5kVA Portable Generator', 2017, 2026, 78000, 95000, '5.5kVA gasoline, recoil start', 'EA')],
        'Water Tanker Truck': [('Isuzu Forward 10,000L Water Tanker', 2018, 2026, 3200000, 3900000, '10,000L tank, water pump and hose reel', 'JAL')],
        'Grass Cutter': [('Kawasaki TJ45 Grass Cutter', 2015, 2026, 16500, 22500, '45cc 2-stroke, shoulder type', None)],
    },
    'Communication Equipment': {
        'Base Radio': [('Kenwood TK-7302 VHF Base Radio', 2015, 2022, 42000, 52000, '25W VHF, with antenna and power supply', 'KW'),
                       ('Motorola XiR M3688 Base Radio', 2021, 2026, 68000, 85000, 'DMR digital/analog, 25W', 'MT')],
        'Two-Way Radio': [('Motorola XiR P3688 Handheld Radio', 2018, 2026, 18500, 24500, 'DMR digital/analog, 5W, with charger', '481'),
                          ('Kenwood TK-3207 Handheld Radio', 2015, 2019, 9800, 12500, 'UHF 5W, with charger', 'B5')],
        'Megaphone': [('Handheld Megaphone with Siren', 2015, 2026, 2800, 4800, '25W, rechargeable', None)],
        'Telephone': [('Panasonic KX-TS880 Telephone', 2015, 2026, 1800, 2600, 'Corded, speakerphone, caller ID', None),
                      ('Panasonic KX-TES824 PABX System', 2015, 2020, 38000, 52000, '8 trunk lines, 24 extensions', 'KX')],
        'CCTV Camera': [('Hikvision 4MP Bullet IP Camera', 2018, 2026, 4800, 7500, '4MP, IR 50m, PoE, IP67', 'DS')],
        'DVR/NVR': [('Hikvision 16-Channel NVR', 2018, 2026, 14500, 22000, '16ch, 2 x 4TB HDD, H.265+', 'DS')],
    },
    'Medical Equipment': {
        'Blood Pressure Monitor': [('Omron HEM-7120 Digital BP Monitor', 2015, 2026, 2400, 3200, 'Upper arm, automatic', None),
                                   ('Aneroid Sphygmomanometer with Stethoscope', 2015, 2026, 1600, 2400, 'Adult cuff', None)],
        'Nebulizer': [('Omron NE-C101 Compressor Nebulizer', 2015, 2026, 2600, 3500, 'Compressor type, adult and child mask', None)],
        'Autoclave': [('Tabletop Steam Autoclave 23L', 2017, 2026, 95000, 145000, '23L, class B, digital display', 'AC')],
        'Weighing Scale': [('Detecto Physician Beam Scale with Height Rod', 2015, 2026, 14500, 19500, 'Up to 180 kg', None),
                           ('Digital Infant Weighing Scale', 2016, 2026, 4500, 6500, 'Up to 20 kg, 5 g precision', None)],
        'Thermal Scanner': [('Infrared Forehead Thermometer', 2020, 2022, 1800, 3200, 'Non-contact, 1-second reading', None)],
        'Oxygen Tank': [('Medical Oxygen Cylinder with Regulator', 2015, 2026, 12500, 18500, '50 lbs, with regulator and humidifier', None)],
        'Stretcher': [('Foldable Aluminum Stretcher', 2015, 2026, 8500, 14500, 'Aluminum alloy, 159 kg capacity', None),
                      ('Spine Board with Head Immobilizer', 2016, 2026, 9800, 15500, 'Polyethylene, X-ray translucent', None)],
        'Wheelchair': [('Standard Steel Wheelchair', 2015, 2026, 6500, 9800, 'Foldable, 18" seat', None)],
    },
    'Agricultural Equipment': {
        'Hand Tractor': [('Kubota RT140 Hand Tractor with Trailer', 2015, 2026, 145000, 195000, '14hp diesel, with rotavator and trailer', 'KBT')],
        'Tractor': [('Kubota L4508 4WD Farm Tractor', 2018, 2026, 1350000, 1650000, '45hp, with disc plow and harrow', 'KBT')],
        'Rice Thresher': [('Axial-Flow Rice Thresher', 2015, 2026, 95000, 145000, '16hp diesel engine, 1 t/h', None)],
        'Water Pump': [('4" Diesel Water Pump Set', 2015, 2026, 32000, 48000, '4" outlet, 7hp diesel engine', None)],
        'Sprayer': [('Motorized Knapsack Sprayer', 2015, 2026, 9800, 14500, '25L, 2-stroke engine', None)],
        'Farm Tool Kit': [('Farm Tool Kit', 2015, 2026, 5500, 9500, 'Shovel, hoe, bolo, rake, pick mattock, sickles', None)],
        'Seedling Tray': [('Plastic Seedling Tray Set (100 pcs)', 2016, 2026, 4500, 7500, '128-cell, for vegetable production', None)],
        'Brush Cutter': [('Stihl FS 230 Brush Cutter', 2016, 2026, 22000, 28500, '36.3cc, shoulder harness', 'ST')],
    },
    'Disaster & Rescue Equipment': {
        'Rescue Boat': [('Inflatable Rescue Boat with 25HP Outboard Motor', 2016, 2026, 480000, 680000, '4.3m, 8 persons, Yamaha 25HP outboard', 'IRB'),
                        ('Fiberglass Rescue Boat with 40HP Outboard Motor', 2019, 2026, 850000, 1150000, '5.5m, 12 persons', 'FRB')],
        'Life Vest': [('Life Vest, Adult (SOLAS approved)', 2015, 2026, 1600, 2800, 'Foam, reflective tape, whistle', None)],
        'Rescue Rope': [('Static Kernmantle Rescue Rope Kit', 2016, 2026, 18500, 32000, '11mm x 100m, with carabiners, pulleys and harness', None)],
        'Emergency Light Tower': [('Mobile Light Tower, 4 x 1000W', 2018, 2026, 420000, 580000, '4 x 1000W metal halide, 9m mast, diesel', 'LT')],
        'Fire Extinguisher': [('ABC Dry Chemical Fire Extinguisher 10 lbs', 2015, 2026, 2800, 4200, '10 lbs, multi-purpose', None),
                              ('HCFC-123 Fire Extinguisher 10 lbs', 2018, 2026, 6500, 8800, 'Clean agent, for electronics', None)],
        'Chainsaw': [('Stihl MS 382 Chainsaw', 2016, 2026, 38000, 46000, '72.2cc, 20" bar', 'ST')],
        'Metal Detector': [('Handheld Metal Detector', 2017, 2026, 4500, 7500, 'Garrett-type, for event security', None)],
    },
}

USEFUL_LIFE = {'Appliances': 5, 'ICT Equipment': 5, 'Office Furniture': 10, 'Office Equipment': 5, 'Motor Vehicle': 7,
               'Heavy Equipment': 10, 'Communication Equipment': 10, 'Medical Equipment': 10, 'Agricultural Equipment': 10,
               'Disaster & Rescue Equipment': 10}
CAT_CODE = {'Appliances': '05990', 'ICT Equipment': '05030', 'Office Furniture': '07010', 'Office Equipment': '05020',
            'Motor Vehicle': '06010', 'Heavy Equipment': '05080', 'Communication Equipment': '05070',
            'Medical Equipment': '05110', 'Agricultural Equipment': '05040', 'Disaster & Rescue Equipment': '05090'}
OFFICE_CODE = {'Office of the Mayor': '1011', 'Information and Communications Technology Office': '1012',
               'Office of the Vice Mayor': '1016', 'Sangguniang Bayan Office': '1021', 'Human Resource Management Office': '1032',
               'Municipal Planning and Development Office': '1041', "Civil Registrar's Office": '1051',
               'General Services Office': '1061', 'Budget Office': '1071', 'Accounting Office': '1081', 'Treasury Office': '1091',
               "Assessor's Office": '1101', 'Municipal Health Office': '4411',
               'Municipal Social Welfare and Development Office': '7611', 'Municipal Agriculture Office': '8711',
               'Municipal Engineering Office': '8751', 'Disaster Risk Reduction and Management Office': '9911'}

# What every office has (article: count per 1.0 size), then what particular offices have
COMMON = {('ICT Equipment', 'Desktop Computer'): 7, ('ICT Equipment', 'Laptop'): 2, ('ICT Equipment', 'Printer'): 4,
          ('ICT Equipment', 'UPS'): 6, ('ICT Equipment', 'Monitor'): 2, ('ICT Equipment', 'External Hard Drive'): 1,
          ('ICT Equipment', 'Scanner'): 1,
          ('Office Furniture', 'Office Desk'): 8, ('Office Furniture', 'Office Chair'): 9, ("Office Furniture", "Visitor's Chair"): 7,
          ('Office Furniture', 'Filing Cabinet'): 5, ('Office Furniture', 'Steel Locker'): 1, ('Office Furniture', 'Bookshelf'): 2,
          ('Office Equipment', 'Calculator'): 2, ('Office Equipment', 'Bulletin Board'): 1, ('Office Equipment', 'Paper Shredder'): 1,
          ('Office Equipment', 'Laminating Machine'): 0.5, ('Office Equipment', 'Binding Machine'): 0.5,
          ('Appliances', 'Air Conditioner'): 3, ('Appliances', 'Electric Fan'): 4, ('Appliances', 'Water Dispenser'): 1,
          ('Appliances', 'Electric Kettle'): 0.6, ('Appliances', 'Refrigerator'): 0.3, ('Appliances', 'Microwave Oven'): 0.3,
          ('Communication Equipment', 'Telephone'): 2, ('Disaster & Rescue Equipment', 'Fire Extinguisher'): 2}
SPECIAL = {
    'Office of the Mayor': {('Motor Vehicle', 'Utility Vehicle'): 2, ('Motor Vehicle', 'Van'): 1, ('ICT Equipment', 'Projector'): 2,
                            ('Office Furniture', 'Conference Table'): 1, ('Appliances', 'Television'): 2, ('Office Equipment', 'Photocopier'): 1,
                            ('Communication Equipment', 'CCTV Camera'): 6, ('Communication Equipment', 'DVR/NVR'): 1},
    'Office of the Vice Mayor': {('Motor Vehicle', 'Utility Vehicle'): 1},
    'Sangguniang Bayan Office': {('ICT Equipment', 'Projector'): 1, ('Office Furniture', 'Conference Table'): 2,
                                 ('Appliances', 'Television'): 1, ('Office Equipment', 'Photocopier'): 1, ('Motor Vehicle', 'Van'): 1},
    'General Services Office': {('Motor Vehicle', 'Pick-up Truck'): 2, ('Motor Vehicle', 'Sedan'): 1, ('Office Equipment', 'Photocopier'): 1,
                                ('Heavy Equipment', 'Generator Set'): 2, ('Appliances', 'Vacuum Cleaner'): 2, ('Heavy Equipment', 'Grass Cutter'): 4,
                                ('Communication Equipment', 'CCTV Camera'): 8, ('Communication Equipment', 'DVR/NVR'): 1,
                                ('Communication Equipment', 'Telephone'): 1, ('Office Furniture', 'Partition Panel'): 6},
    'Treasury Office': {('Office Equipment', 'Cash Counting Machine'): 3, ('ICT Equipment', 'Printer'): 4, ('Office Equipment', 'Photocopier'): 1,
                        ('Office Furniture', 'Partition Panel'): 4, ('Communication Equipment', 'CCTV Camera'): 4},
    "Assessor's Office": {('ICT Equipment', 'Printer'): 2, ('Office Equipment', 'Photocopier'): 1, ('ICT Equipment', 'Tablet'): 3},
    'Accounting Office': {('Office Equipment', 'Photocopier'): 1},
    "Civil Registrar's Office": {('ICT Equipment', 'Printer'): 2, ('ICT Equipment', 'Scanner'): 2},
    'Municipal Planning and Development Office': {('ICT Equipment', 'Projector'): 1, ('ICT Equipment', 'Tablet'): 2, ('Motor Vehicle', 'Motorcycle'): 1},
    'Information and Communications Technology Office': {('ICT Equipment', 'Network Switch'): 8, ('ICT Equipment', 'Router'): 5,
                                                         ('ICT Equipment', 'UPS'): 4, ('ICT Equipment', 'Laptop'): 3, ('ICT Equipment', 'External Hard Drive'): 3,
                                                         ('Communication Equipment', 'CCTV Camera'): 10, ('Communication Equipment', 'DVR/NVR'): 2,
                                                         ('Communication Equipment', 'Telephone'): 1, ('ICT Equipment', 'Projector'): 1},
    'Municipal Health Office': {('Motor Vehicle', 'Ambulance'): 2, ('Motor Vehicle', 'Motorcycle'): 2,
                                ('Medical Equipment', 'Blood Pressure Monitor'): 10, ('Medical Equipment', 'Nebulizer'): 6, ('Medical Equipment', 'Autoclave'): 2,
                                ('Medical Equipment', 'Weighing Scale'): 6, ('Medical Equipment', 'Thermal Scanner'): 6, ('Medical Equipment', 'Oxygen Tank'): 6,
                                ('Medical Equipment', 'Stretcher'): 4, ('Medical Equipment', 'Wheelchair'): 4, ('Appliances', 'Refrigerator'): 3,
                                ('Heavy Equipment', 'Generator Set'): 1},
    'Municipal Social Welfare and Development Office': {('Motor Vehicle', 'Van'): 1, ('Motor Vehicle', 'Motorcycle'): 1, ('ICT Equipment', 'Tablet'): 4,
                                                        ('Medical Equipment', 'Wheelchair'): 6, ('Office Equipment', 'Photocopier'): 1, ('Appliances', 'Television'): 1},
    'Municipal Agriculture Office': {('Agricultural Equipment', 'Hand Tractor'): 8, ('Agricultural Equipment', 'Tractor'): 2,
                                     ('Agricultural Equipment', 'Rice Thresher'): 6, ('Agricultural Equipment', 'Water Pump'): 8,
                                     ('Agricultural Equipment', 'Sprayer'): 12, ('Agricultural Equipment', 'Farm Tool Kit'): 10,
                                     ('Agricultural Equipment', 'Seedling Tray'): 8, ('Agricultural Equipment', 'Brush Cutter'): 4,
                                     ('Motor Vehicle', 'Pick-up Truck'): 1, ('Motor Vehicle', 'Motorcycle'): 3},
    'Municipal Engineering Office': {('Heavy Equipment', 'Backhoe Loader'): 2, ('Heavy Equipment', 'Bulldozer'): 1, ('Heavy Equipment', 'Road Roller'): 1,
                                     ('Heavy Equipment', 'Concrete Mixer'): 3, ('Heavy Equipment', 'Water Tanker Truck'): 1, ('Heavy Equipment', 'Generator Set'): 2,
                                     ('Motor Vehicle', 'Dump Truck'): 4, ('Motor Vehicle', 'Pick-up Truck'): 2, ('ICT Equipment', 'Printer'): 1,
                                     ('Heavy Equipment', 'Grass Cutter'): 4},
    'Disaster Risk Reduction and Management Office': {('Motor Vehicle', 'Ambulance'): 2, ('Motor Vehicle', 'Pick-up Truck'): 1,
                                                      ('Disaster & Rescue Equipment', 'Rescue Boat'): 3, ('Disaster & Rescue Equipment', 'Life Vest'): 40,
                                                      ('Disaster & Rescue Equipment', 'Rescue Rope'): 6, ('Disaster & Rescue Equipment', 'Emergency Light Tower'): 2,
                                                      ('Disaster & Rescue Equipment', 'Fire Extinguisher'): 10, ('Disaster & Rescue Equipment', 'Chainsaw'): 4,
                                                      ('Disaster & Rescue Equipment', 'Metal Detector'): 4, ('Communication Equipment', 'Base Radio'): 3,
                                                      ('Communication Equipment', 'Two-Way Radio'): 30, ('Communication Equipment', 'Megaphone'): 8,
                                                      ('Heavy Equipment', 'Generator Set'): 3, ('Medical Equipment', 'Stretcher'): 8,
                                                      ('Medical Equipment', 'Oxygen Tank'): 4, ('Medical Equipment', 'Blood Pressure Monitor'): 4,
                                                      ('ICT Equipment', 'Laptop'): 2, ('Appliances', 'Television'): 1},
}

PLACES = {('Motor Vehicle',): 'Motor Pool', ('Heavy Equipment',): 'Equipment Yard'}

# ── Build the assets ───────────────────────────────────────────────────────────────────
staff = {}      # office -> [(username, full name, position)]
users_sql = []
usernames = set()


def username_for(name):
    parts = name.replace('Ma. ', 'Ma ').split()
    first, last = parts[0], parts[-1] if parts[-2] not in ('Dela', 'De') else parts[-2] + parts[-1]
    base = (first[0] + last).lower().replace(' ', '').replace('.', '').replace('ñ', 'n')
    u, n = base, 2
    while u in usernames:
        u = f'{base}{n}'
        n += 1
    usernames.add(u)
    return u


for office, (_, positions, _) in OFFICES.items():
    staff[office] = []
    for pos in positions:
        name = person()
        staff[office].append((username_for(name), name, pos))

assets = []        # dicts
batches = []       # each procurement batch shares a PAR


def models_for(cat, art, year):
    opts = [m for m in CAT[cat][art] if m[1] <= year <= m[2]]
    return opts or None


def plan_office(office, needs):
    building, _, size = OFFICES[office]
    for (cat, art), per in needs.items():
        total = per * size * R.uniform(0.75, 1.25) * 1.2
        total = int(total) + (1 if R.random() < total - int(total) else 0)
        if total <= 0:
            continue
        # bought in waves over the years
        waves = 1 if total <= 2 else R.choice([1, 2, 2, 3, 3, 4]) if total < 12 else R.choice([2, 3, 4])
        counts = [total // waves + (1 if i < total % waves else 0) for i in range(waves)]
        for count in counts:
            if count == 0:
                continue
            for _ in range(10):
                year = R.randint(START_YEAR, TODAY.year)
                if models_for(cat, art, year):
                    break
            else:
                continue
            model = R.choice(models_for(cat, art, year))
            last_day = TODAY - dt.timedelta(days=12) if year == TODAY.year else dt.date(year, 12, 20)
            acq = rand_date(dt.date(year, 1, 15), last_day)
            price = peso(model[3], model[4], 50 if model[4] < 100000 else 1000)
            batches.append(dict(office=office, cat=cat, art=art, model=model, acq=acq, price=price, count=count))


for office in OFFICES:
    plan_office(office, COMMON)
    plan_office(office, SPECIAL.get(office, {}))

R.shuffle(batches)
par_counter = {}


def next_par(day):
    key = day.strftime('%Y-%m')
    par_counter[key] = par_counter.get(key, 0) + 1
    return f'{key}:{par_counter[key]:04d}'


def room_for(office, cat):
    building = OFFICES[office][0]
    if cat in ('Motor Vehicle',):
        return f'{building}, Motor Pool' if office in ('General Services Office', 'Municipal Engineering Office') else f'{building}, Parking Area'
    if cat == 'Heavy Equipment' and office == 'Municipal Engineering Office':
        return f'{building}, Equipment Yard'
    rooms = ROOMS.get(office)
    return f'{building}, {R.choice(rooms)}' if rooms else building


for b in sorted(batches, key=lambda b: b['acq']):
    holders = staff[b['office']]
    # big items go to the office head; the rest to a custodian, or split among staff for personal-use items
    personal = b['art'] in ('Desktop Computer', 'Laptop', 'Office Chair', 'Office Desk', 'Tablet', 'Two-Way Radio', 'UPS', 'Monitor')
    head_item = b['cat'] in ('Motor Vehicle', 'Heavy Equipment') or b['model'][4] >= 400000
    recent = (TODAY - b['acq']).days < 20
    pars = {}
    for i in range(b['count']):
        if recent and b['office'] == 'General Services Office':
            holder = None
        elif head_item:
            holder = holders[0]
        elif personal:
            holder = holders[i % len(holders)]
        else:
            holder = holders[min(1, len(holders) - 1)]
        key = holder[0] if holder else None
        if key and key not in pars:
            pars[key] = next_par(b['acq'])
        model = b['model']
        a = dict(office=b['office'], cat=b['cat'], art=b['art'], desc=model[0], specs=model[5], acq=b['acq'],
                 price=b['price'], holder=holder, par=pars.get(key), location=room_for(b['office'], b['cat']),
                 serial=serial_no(model[6], 8 if model[6] else 0) if model[6] else None)
        # an end user other than the accountable person (e.g. the clerk who uses the PC)
        if holder and personal and R.random() < 0.25 and len(holders) > 1:
            a['end_user'] = R.choice([h for h in holders if h != holder])
        assets.append(a)

# ── What happened to each asset since ───────────────────────────────────────────────────
REPAIRABLE_KINDS = {'Desktop Computer', 'Laptop', 'Printer', 'UPS', 'Air Conditioner', 'Photocopier', 'Electric Fan',
                    'Office Chair', 'Two-Way Radio', 'Hand Tractor', 'Generator Set', 'Scanner', 'Projector', 'Refrigerator',
                    'Base Radio', 'Water Pump', 'Rice Thresher', 'Chainsaw', 'Brush Cutter', 'Grass Cutter', 'Autoclave'}
GSO = 'General Services Office'
for a in assets:
    age = (TODAY - a['acq']).days / 365.25
    life = USEFUL_LIFE[a['cat']]
    ratio = age / life
    a['events'] = []
    a['maint'] = []
    a['transfer'] = None
    a['disposal'] = None
    r = R.random()
    if a['art'] in ('Typewriter', 'Fax Machine', 'Thermal Scanner') and ratio > 0.8:
        r = min(r, 0.2)
    # odds by age band: past its useful life, many are disposed or waiting for disposal; a few
    # of the rest are under repair at any one time
    if ratio > 1.2:
        a['fate'] = 'disposed' if r < 0.30 else 'for_disposal' if r < 0.40 else 'repair' if r < 0.45 else 'in_use'
    elif ratio > 0.9:
        a['fate'] = 'for_disposal' if r < 0.07 else 'repair' if r < 0.13 else 'in_use'
    elif ratio > 0.35:
        a['fate'] = 'repair' if r < 0.03 else 'in_use'
    else:
        a['fate'] = 'in_use'
    if a['fate'] == 'repair' and a['art'] not in REPAIRABLE_KINDS and a['cat'] not in ('Motor Vehicle', 'Heavy Equipment'):
        a['fate'] = 'in_use'
    # transfers: movable items, issued at least a year
    if a['holder'] and a['cat'] not in ('Heavy Equipment',) and age > 1.3 and R.random() < 0.07 and a['fate'] != 'disposed':
        a['transfer'] = True

for a in assets:
    a['cond'] = {'disposed': 'UNSERVICEABLE', 'for_disposal': 'UNSERVICEABLE', 'repair': 'REPAIRABLE'}.get(a['fate'])
    if not a['cond']:
        age = (TODAY - a['acq']).days / 365.25
        ratio = age / USEFUL_LIFE[a['cat']]
        a['cond'] = 'NEW' if age < 0.6 else 'GOOD' if ratio < 0.5 else 'SERVICEABLE'

# serials: per category in order of acquisition
by_cat = {}
for a in sorted(assets, key=lambda a: (a['cat'], a['acq'])):
    by_cat[a['cat']] = by_cat.get(a['cat'], 0) + 1
    a['serial_no'] = by_cat[a['cat']]


def pn(a, office):
    return f"{a['acq'].year}-{CAT_CODE[a['cat']]}-{a['serial_no']:03d}-{OFFICE_CODE[office]}"


# transfers: to another office, a new accountable person, a new PAR
TRANSFER_REASONS = ['Reassigned to the receiving office per memo from the Office of the Mayor',
                    'Re-issued after the previous end user retired', 'Needed by the receiving office for frontline services',
                    'Redistribution of equipment after office reorganization', 'Transferred upon request of the receiving office head',
                    'Previous accountable officer resigned']
offices_list = list(OFFICES)
for a in assets:
    if a['transfer']:
        to_office = R.choice([o for o in offices_list if o != a['office']])
        start = a['acq'] + dt.timedelta(days=400)
        end = TODAY - dt.timedelta(days=30)
        when = rand_date(start, end)
        to_holder = R.choice(staff[to_office])
        a['transfer'] = dict(from_office=a['office'], to_office=to_office, date=when, from_holder=a['holder'], to_holder=to_holder,
                             reason=R.choice(TRANSFER_REASONS), old_pn=pn(a, a['office']), old_par=a['par'],
                             new_par=next_par(when), location=room_for(to_office, a['cat']))
        a['office'] = to_office
        a['holder'] = to_holder
        a['par'] = a['transfer']['new_par']
        a['location'] = a['transfer']['location']
        a.pop('end_user', None)

for a in assets:
    a['pn'] = pn(a, a['office'])

# maintenance: preventive service for vehicles, heavy equipment, aircon, generators; repairs for the rest
SHOPS = ['GSO Motor Pool', 'GSO Maintenance Section', 'ICT Office Technical Support', 'JRS Aircon Services',
         'Toyota San Jose (authorized service center)', 'Isuzu Nueva Ecija Service Center', 'Allan Electronics Repair Shop',
         'Engineering Office Mechanic']
REPAIR = {
    'Desktop Computer': [('Computer does not boot; power supply failed', 'Replaced power supply unit; cleaned internal components', [('PART', 'Power supply unit 500W', 'pc', 1, 1850)], 'ICT Office Technical Support'),
                         ('System slow and freezing; failing hard disk', 'Replaced HDD with 512GB SSD, reinstalled OS and office software', [('PART', 'SSD 512GB SATA', 'pc', 1, 2450), ('LABOR', 'OS installation and data migration', 'job', 1, 500)], 'ICT Office Technical Support'),
                         ('No display; RAM module failure', 'Replaced 8GB DDR4 RAM module', [('PART', 'RAM 8GB DDR4', 'pc', 1, 1450)], 'ICT Office Technical Support')],
    'Laptop': [('Battery no longer holds charge', 'Replaced battery', [('PART', 'Replacement battery', 'pc', 1, 3200)], 'Allan Electronics Repair Shop'),
               ('Cracked screen', 'Replaced LCD panel', [('PART', '14" LCD panel', 'pc', 1, 4800), ('LABOR', 'Installation', 'job', 1, 800)], 'Allan Electronics Repair Shop')],
    'Printer': [('Paper jams and faded prints', 'Cleaned print head, replaced pickup roller', [('PART', 'Pickup roller assembly', 'pc', 1, 650), ('LABOR', 'Head cleaning and servicing', 'job', 1, 500)], 'ICT Office Technical Support'),
                ('Waste ink pad full (blinking lights)', 'Reset ink pad counter, replaced waste ink pad', [('PART', 'Waste ink pad', 'pc', 1, 450), ('LABOR', 'Service and counter reset', 'job', 1, 600)], 'Allan Electronics Repair Shop')],
    'UPS': [('UPS beeps and shuts down; battery weak', 'Replaced 12V 7Ah battery', [('PART', 'Sealed lead-acid battery 12V 7Ah', 'pc', 1, 950)], 'ICT Office Technical Support')],
    'Air Conditioner': [('Not cooling; low refrigerant', 'Leak test, recharged refrigerant, cleaned filters and coils', [('PART', 'Refrigerant R32', 'kg', 1, 1800), ('LABOR', 'Leak repair and recharging', 'job', 1, 1500)], 'JRS Aircon Services'),
                        ('Unit trips the breaker; compressor capacitor failed', 'Replaced capacitor and contactor', [('PART', 'Run capacitor 45uF', 'pc', 1, 650), ('PART', 'Contactor', 'pc', 1, 850), ('LABOR', 'Electrical repair', 'job', 1, 1200)], 'JRS Aircon Services')],
    'Photocopier': [('Lines on copies; drum worn out', 'Replaced drum unit and developer', [('PART', 'Drum unit', 'pc', 1, 8500), ('PART', 'Developer', 'pc', 1, 3200), ('LABOR', 'Service', 'job', 1, 1500)], 'Canon Business Solutions'),],
    'Electric Fan': [('Motor runs hot and slow', 'Replaced capacitor and bushing', [('PART', 'Fan capacitor', 'pc', 1, 120), ('PART', 'Bushing set', 'set', 1, 150), ('LABOR', 'Repair', 'job', 1, 250)], 'GSO Maintenance Section')],
    'Office Chair': [('Gas lift no longer holds height', 'Replaced gas cylinder', [('PART', 'Gas lift cylinder', 'pc', 1, 650)], 'GSO Maintenance Section')],
    'Two-Way Radio': [('No transmit; antenna and battery damaged', 'Replaced antenna and battery pack', [('PART', 'Antenna', 'pc', 1, 950), ('PART', 'Li-ion battery pack', 'pc', 1, 2800)], 'DRRMO Communications')],
    'Hand Tractor': [('Engine hard to start; injector clogged', 'Cleaned injector, replaced fuel filter, oil change', [('PART', 'Fuel filter', 'pc', 1, 350), ('PART', 'Engine oil 4L', 'gal', 1, 1450), ('LABOR', 'Engine tune-up', 'job', 1, 1500)], 'Engineering Office Mechanic')],
    'Generator Set': [('Fails to start on ATS signal; battery dead', 'Replaced starter battery, serviced engine', [('PART', 'Battery 2SM', 'pc', 1, 5800), ('LABOR', 'Service', 'job', 1, 2000)], 'Engineering Office Mechanic')],
}
SERVICE = {
    'Motor Vehicle': [('Periodic maintenance service at 10,000 km', 'Change oil and oil filter, checked brakes, tires and fluids',
                       [('PART', 'Engine oil 15W-40', 'L', 7, 420), ('PART', 'Oil filter', 'pc', 1, 650), ('LABOR', 'PMS labor', 'job', 1, 1800)], 'Toyota San Jose (authorized service center)'),
                      ('Worn brake pads, squeaking brakes', 'Replaced front brake pads, resurfaced rotors',
                       [('PART', 'Front brake pads', 'set', 1, 3200), ('LABOR', 'Brake service and rotor resurfacing', 'job', 1, 1800)], 'GSO Motor Pool'),
                      ('Battery weak, hard starting', 'Replaced battery', [('PART', 'Battery 3SM', 'pc', 1, 6800)], 'GSO Motor Pool')],
    'Heavy Equipment': [('Scheduled 250-hour service', 'Changed engine oil and filters, greased all fittings, checked hydraulics',
                         [('PART', 'Engine oil 15W-40', 'L', 16, 420), ('PART', 'Filter set (oil, fuel, air)', 'set', 1, 6500), ('LABOR', 'Preventive maintenance', 'job', 1, 3500)], 'Engineering Office Mechanic'),
                        ('Hydraulic hose leak', 'Replaced hydraulic hose and topped up hydraulic oil',
                         [('PART', 'Hydraulic hose assembly', 'pc', 1, 4800), ('PART', 'Hydraulic oil', 'L', 10, 380), ('LABOR', 'Repair', 'job', 1, 2500)], 'Engineering Office Mechanic')],
    'Air Conditioner': [('Semi-annual cleaning', 'General cleaning of indoor and outdoor units, checked amperage and refrigerant',
                         [('LABOR', 'General cleaning (split type)', 'unit', 1, 1500)], 'JRS Aircon Services')],
}


def maint_record(a, when, kind, status):
    art = a['art']
    if kind == 'PREVENTIVE':
        opts = SERVICE.get(a['cat']) or SERVICE.get(art) or SERVICE['Air Conditioner']
    else:
        opts = REPAIR.get(art) or [(f'{art} not working properly', f'Inspected and repaired {art.lower()}',
                                    [('LABOR', 'Inspection and repair', 'job', 1, R.choice([500, 800, 1200]))], 'GSO Maintenance Section')]
    findings, actions, items, shop = R.choice(opts)
    if status != 'COMPLETED':
        items = []
    return dict(type=kind, date=when, findings=findings, actions=actions if status == 'COMPLETED' else 'For repair; awaiting parts and assessment',
                items=items, shop=shop, status=status)


for a in assets:
    start = a['acq'] + dt.timedelta(days=200)
    end = TODAY - dt.timedelta(days=20)
    if a['fate'] == 'disposed':
        end = min(end, a['acq'] + dt.timedelta(days=int(365.25 * USEFUL_LIFE[a['cat']] * 1.1)))
    serviced = a['cat'] in ('Motor Vehicle', 'Heavy Equipment') or a['art'] in ('Air Conditioner', 'Generator Set')
    if serviced and end > start:
        n = min(4, max(0, int((end - start).days / 365) + R.randint(-1, 1)))
        for _ in range(n):
            a['maint'].append(maint_record(a, rand_date(start, end), 'PREVENTIVE', 'COMPLETED'))
    if end > start and R.random() < (0.18 if a['cond'] != 'NEW' else 0):
        a['maint'].append(maint_record(a, rand_date(start, end), 'REPAIR', 'COMPLETED'))
    if a['fate'] == 'repair':
        a['maint'].append(maint_record(a, rand_date(TODAY - dt.timedelta(days=90), TODAY - dt.timedelta(days=3)), 'REPAIR', 'ONGOING'))
    a['maint'].sort(key=lambda m: m['date'])

# disposals (IIRUP): sale by public bidding mostly
DISPOSAL_REASONS = {
    'ICT Equipment': ('Beyond economical repair; parts no longer available', 'Unit fails to power on; motherboard and power circuit damaged. Repair cost exceeds 50% of replacement cost.'),
    'Appliances': ('Beyond economical repair', 'Compressor/motor burnt out; unit no longer operational. Rusted body and housing.'),
    'Office Furniture': ('Worn out and broken from long use', 'Broken frame and drawers, rusted; no longer safe or usable.'),
    'Office Equipment': ('Obsolete and unserviceable', 'Mechanism worn out; replacement parts no longer manufactured.'),
    'Motor Vehicle': ('Beyond economical repair after long service', 'Engine overhaul needed, chassis corroded; repair cost exceeds the vehicle value.'),
    'Heavy Equipment': ('Unserviceable after long service', 'Engine and hydraulic system worn out; major overhaul not economical.'),
    'Communication Equipment': ('Obsolete and unserviceable', 'No transmit/receive; parts no longer available for this model.'),
    'Medical Equipment': ('Unserviceable; no longer accurate or safe for patient use', 'Fails calibration; housing cracked.'),
    'Agricultural Equipment': ('Unserviceable after years of field use', 'Engine seized, frame corroded.'),
    'Disaster & Rescue Equipment': ('Unserviceable; failed inspection', 'Damaged and no longer safe for rescue operations.'),
}
MAYOR = staff['Office of the Mayor'][0][1]
or_counter = [8_812_340]
for a in assets:
    if a['fate'] in ('disposed', 'for_disposal'):
        life_end = a['acq'] + dt.timedelta(days=int(365.25 * USEFUL_LIFE[a['cat']]))
        if a['fate'] == 'disposed':
            insp = rand_date(max(life_end, a['acq'] + dt.timedelta(days=400)), TODAY - dt.timedelta(days=120))
        else:
            insp = rand_date(TODAY - dt.timedelta(days=150), TODAY - dt.timedelta(days=5))
        reason, findings = DISPOSAL_REASONS[a['cat']]
        method = 'SALE'
        if a['cat'] in ('Medical Equipment',) or a['art'] in ('Fire Extinguisher', 'Life Vest', 'Seedling Tray', 'Farm Tool Kit'):
            method = 'DESTRUCTION'
        elif a['art'] in ('Office Desk', 'Filing Cabinet', 'Bookshelf') and R.random() < 0.3:
            method = 'TRANSFER'
        status = 'COMPLETED' if a['fate'] == 'disposed' else R.choice(['PENDING', 'PENDING', 'APPROVED'])
        appraised = round(a['price'] * R.uniform(0.03, 0.10), -1) if method == 'SALE' else None
        d = dict(date=insp, reason=reason, findings=findings, method=method, status=status, appraised=appraised,
                 approved_by=f'{MAYOR}, Municipal Mayor' if status != 'PENDING' else None)
        if status == 'COMPLETED' and method == 'SALE':
            or_counter[0] += R.randint(3, 40)
            d['or'] = str(or_counter[0])
            d['amount'] = round(appraised * R.uniform(1.0, 1.35), -1)
        a['disposal'] = d
        if a['fate'] == 'disposed' and a['maint']:
            a['maint'] = [m for m in a['maint'] if m['date'] < insp]

# a few requests still waiting for the admin, filed by staff
pending_transfers = []
for a in R.sample([x for x in assets if x['fate'] == 'in_use' and x['holder'] and not x['transfer']
                   and x['cat'] in ('ICT Equipment', 'Office Furniture', 'Appliances')], 4):
    to_office = R.choice([o for o in offices_list if o != a['office']])
    pending_transfers.append(dict(asset=a, to_office=to_office, to_holder=R.choice(staff[to_office]),
                                  date=TODAY - dt.timedelta(days=R.randint(1, 6)), reason=R.choice(TRANSFER_REASONS),
                                  requester=staff[a['office']][min(1, len(staff[a['office']]) - 1)]))

# ── SQL ────────────────────────────────────────────────────────────────────────────────
out = []
w = out.append
w('-- Realistic GSO inventory, generated by generate_realistic_seed.py. Deletes ALL asset data first.')
w('SET NAMES utf8mb4;')
w('SET FOREIGN_KEY_CHECKS = 0;')
w('START TRANSACTION;')
for t in ['maintenance_items', 'maintenance_photos', 'maintenance_summaries', 'maintenance_ledger', 'deleted_maintenance',
          'disposal_justifications', 'disposal_ledger', 'deleted_disposal', 'asset_par_issuances', 'property_return_slips',
          'asset_transfer_requests', 'asset_history', 'evidence_photos', 'ai_recommendations', 'request_reminders',
          'deleted_assets', 'device_records', 'equipment_records', 'audit_log_digests', 'assets']:
    w(f'DELETE FROM `{t}`;')
w("DELETE FROM audit_logs WHERE module IN ('Assets','AssetHistory','Maintenance','Disposal','Transfer','Transfers','Reports');")
w('COMMIT;')
for t in ['assets', 'asset_history', 'maintenance_ledger', 'maintenance_items', 'disposal_ledger', 'asset_transfer_requests',
          'property_return_slips', 'asset_par_issuances']:
    w(f'ALTER TABLE `{t}` AUTO_INCREMENT = 1;')
w('SET FOREIGN_KEY_CHECKS = 1;')
w('START TRANSACTION;')

# who records things: the GSO admin (first ADMIN account)
w("SET @admin := (SELECT MIN(user_id) FROM users WHERE role = 'ADMIN' AND is_active = 1);")
for office in OFFICES:
    w(f"SET @o{OFFICE_CODE[office]} := (SELECT office_id FROM offices WHERE office_name = {q(office)});")
for cat in CAT:
    w(f"SET @c{CAT_CODE[cat]} := (SELECT category_id FROM categories WHERE category_name = {q(cat)});")

# staff accounts (no usable password: an admin resets one to let a person sign in)
for office, people in staff.items():
    for uname, name, pos in people:
        w(f"INSERT INTO users (username, password_hash, full_name, role, office_id, is_active, email, must_change_password, two_factor_enabled, created_at) "
          f"SELECT {q(uname)}, '!no-password-set', {q(name)}, 'STAFF', @o{OFFICE_CODE[office]}, 1, {q(uname + '@sanjosegso.local')}, 1, 0, '2015-01-05 01:00:00' "
          f"FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM users WHERE username = {q(uname)});")
w('CALL sp_personnel_sync_accounts();')
for office, people in staff.items():
    for uname, name, pos in people:
        var = '@p_' + uname
        w(f"SET {var} := (SELECT p.personnel_id FROM personnel p JOIN users u ON u.user_id = p.user_id WHERE u.username = {q(uname)});")
        w(f"UPDATE personnel SET position = {q(pos)}, office_id = @o{OFFICE_CODE[office]} WHERE personnel_id = {var};")
        w(f"INSERT IGNORE INTO personnel_offices (personnel_id, office_id) VALUES ({var}, @o{OFFICE_CODE[office]});")

art_vars = {}
for cat, arts in CAT.items():
    for art in arts:
        v = f"@a{len(art_vars)}"
        art_vars[(cat, art)] = v
        w(f"SET {v} := (SELECT article_id FROM articles WHERE category_id = @c{CAT_CODE[cat]} AND article_name = {q(art)});")


def pvar(holder):
    return '@p_' + holder[0] if holder else 'NULL'


def lifecycle(a):
    # as the app does it: an asset is DISPOSED from the time its disposal record is opened
    if a['disposal']:
        return 'DISPOSED'
    if a['fate'] == 'repair':
        return 'UNDER_MAINTENANCE'
    if not a['holder']:
        return 'REGISTERED'
    return 'TRANSFERRED' if a['transfer'] else 'ASSIGNED'


hist = []
mrows, mitems, drows, trows, srows, prows = [], [], [], [], [], []
mid = did = tid = sid = 0
prs_counter = {}
for i, a in enumerate(sorted(assets, key=lambda a: (a['acq'], a['cat'], a['serial_no'])), start=1):
    a['id'] = i
    remarks = None
    if a['disposal'] and a['disposal']['status'] == 'COMPLETED':
        remarks = 'Disposed per IIRUP' + (f", sold at public auction (OR No. {a['disposal']['or']})" if a['disposal'].get('or') else '')
    elif a['fate'] == 'for_disposal':
        remarks = 'For disposal; included in the IIRUP'
    w('INSERT INTO assets (asset_id, property_number, par_number, description, category_id, article_id, quantity, acquisition_date, unit_value, '
      'office_id, personnel_id, current_user_personnel_id, physical_count, location, `condition`, lifecycle_status, remarks, is_deleted, '
      'created_at, updated_at, serial_number, specifications, shortage_overage_qty, shortage_overage_value) VALUES ('
      + ', '.join([str(i), q(a['pn']), q(a['par']), q(a['desc']), f"@c{CAT_CODE[a['cat']]}", art_vars[(a['cat'], a['art'])], '1',
                   q(a['acq']), f"{a['price']:.2f}", f"@o{OFFICE_CODE[a['office']]}", pvar(a['holder']), pvar(a.get('end_user')), '1',
                   q(a['location']), q(a['cond']), q(lifecycle(a)), q(remarks), '0', q(at(a['acq'])), q(at(TODAY - dt.timedelta(days=R.randint(0, 60)))),
                   q(a['serial']), q(a['specs']), '0', '0.00']) + ');')
    first_office = a['transfer']['from_office'] if a['transfer'] else a['office']
    first_holder = a['transfer']['from_holder'] if a['transfer'] else a['holder']
    first_pn = a['transfer']['old_pn'] if a['transfer'] else a['pn']
    first_par = a['transfer']['old_par'] if a['transfer'] else a['par']
    reg = at(a['acq'], 8, 11)
    hist.append((i, 'REGISTERED', None, first_office, reg, f'Asset registered: {first_pn}'))
    if first_holder:
        issued = workday(a['acq'] + dt.timedelta(days=R.randint(0, 6)))
        hist.append((i, 'ASSIGNED', None, first_office, at(issued, 13, 16),
                     f'Issued to {first_holder[1]}, {first_holder[2]}, on PAR {first_par}'))
    t = a['transfer']
    if t:
        tid += 1
        sid += 1
        yr = t['date'].year
        prs_counter[yr] = prs_counter.get(yr, 0) + 1
        slip = f'PRS-{yr}-{prs_counter[yr]:04d}'
        when = at(t['date'], 9, 15)
        requester = staff[t['from_office']][min(1, len(staff[t['from_office']]) - 1)]
        trows.append(f"({tid}, {i}, @o{OFFICE_CODE[t['from_office']]}, @o{OFFICE_CODE[t['to_office']]}, {pvar(t['to_holder'])}, {q(t['location'])}, {q(t['reason'])}, "
                     f"'APPROVED', (SELECT user_id FROM users WHERE username = {q(requester[0])}), {q(when - dt.timedelta(days=R.randint(1, 5)))}, @admin, {q(when)}, NULL)")
        srows.append(f"({sid}, {q(slip)}, {tid}, {i}, 'RETURNED_TO_STOCK', {q(t['from_office'])}, {pvar(t['from_holder'])}, {q(t['from_holder'][1])}, {q(t['from_holder'][2])}, "
                     f"{q(t['date'])}, {q(t['old_pn'])}, {q(t['old_par'])}, {q(a['desc'])}, {q(a['specs'])}, {a['price']:.2f}, {q(a['acq'])}, @admin, {q(when)})")
        # the original PAR (kept on the first reissue) and the new one
        prows.append(f"({q(t['old_par'])}, {i}, NULL, NULL, {pvar(t['from_holder'])}, {q(t['from_holder'][1])}, {q(t['from_holder'][2])}, {q(t['from_office'])}, "
                     f"{q(a['acq'])}, {q(t['old_pn'])}, {q(a['desc'])}, {q(a['specs'])}, {a['price']:.2f}, {q(a['acq'])}, 1, @admin, {q(when)})")
        prows.append(f"({q(t['new_par'])}, {i}, {tid}, {sid}, {pvar(t['to_holder'])}, {q(t['to_holder'][1])}, {q(t['to_holder'][2])}, {q(t['to_office'])}, "
                     f"{q(t['date'])}, {q(a['pn'])}, {q(a['desc'])}, {q(a['specs'])}, {a['price']:.2f}, {q(a['acq'])}, 0, @admin, {q(when)})")
        note = (f"Transferred from {t['from_office']} to {t['to_office']} ({t['location']}), accountable: {t['to_holder'][1]}. Reason: {t['reason']}"
                f". Property number changed from {t['old_pn']} to {a['pn']}. Returned by {t['from_holder'][1]} on a Property Return Slip"
                f". New PAR {t['new_par']} replaces {t['old_par']}")
        hist.append((i, 'TRANSFERRED', t['from_office'], t['to_office'], when, note))
    for m in a['maint']:
        mid += 1
        cost = sum(q_ * c for (_, _, _, q_, c) in m['items']) if m['items'] else None
        created = at(m['date'], 8, 15)
        mrows.append(f"({mid}, {i}, {q(m['type'])}, {q(m['findings'])}, {q(m['actions'])}, {q(m['shop'])}, {q(m['date'])}, "
                     f"{q(round(cost, 2)) if cost else 'NULL'}, {q(m['status'])}, @admin, {q(created)}, {q(created)}, 'APPROVED')")
        for n, (kind, part, unit, qty, uc) in enumerate(m['items'], start=1):
            mitems.append(f"({mid}, {n}, {q(kind)}, {q(part)}, {q(unit)}, {qty}, {uc:.2f}, {qty * uc:.2f})")
        hist.append((i, 'MAINTENANCE', None, None, created, f"Maintenance logged ({m['type']}): {m['findings']}"
                     + ('' if m['status'] == 'COMPLETED' else '. Asset marked repairable')))
    d = a['disposal']
    if d:
        did += 1
        created = at(d['date'], 9, 15)
        drows.append(f"({did}, {i}, {q(d['reason'])}, {q(d['findings'])}, {q(d['method'])}, {q(d['status'])}, {q(d['date'])}, {q(d['approved_by'])}, "
                     f"{q(d['appraised'])}, {q(d.get('or'))}, {q(d.get('amount'))}, @admin, {q(created)}, {q(created)}, 'APPROVED')")
        hist.append((i, 'DISPOSAL', None, None, created, f"Disposal logged ({d['method']}): {d['reason']}"))
        if d['status'] == 'COMPLETED':
            done = workday(d['date'] + dt.timedelta(days=R.randint(30, 90)))
            hist.append((i, 'DISPOSAL', None, None, at(done), 'Disposal completed' + (f" (OR No. {d['or']})" if d.get('or') else '')))

pending_rows = []
for p in pending_transfers:
    a = p['asset']
    tid += 1
    pending_rows.append(f"({tid}, {a['id']}, @o{OFFICE_CODE[a['office']]}, @o{OFFICE_CODE[p['to_office']]}, {pvar(p['to_holder'])}, "
                        f"{q(room_for(p['to_office'], a['cat']))}, {q(p['reason'])}, 'PENDING_APPROVAL', "
                        f"(SELECT user_id FROM users WHERE username = {q(p['requester'][0])}), {q(at(p['date']))}, NULL, NULL, NULL)")


def chunks(rows, n=400):
    for k in range(0, len(rows), n):
        yield rows[k:k + n]


cols_h = '(asset_id, event_type, from_office_id, to_office_id, performed_by, event_date, notes)'
hrows = []
for (aid, ev, fo, to, when, note) in sorted(hist, key=lambda h: h[4]):
    hrows.append(f"({aid}, '{ev}', {('@o' + OFFICE_CODE[fo]) if fo else 'NULL'}, {('@o' + OFFICE_CODE[to]) if to else 'NULL'}, @admin, {q(when)}, {q(note)})")
for c in chunks(hrows):
    w(f'INSERT INTO asset_history {cols_h} VALUES\n' + ',\n'.join(c) + ';')
for c in chunks(trows + pending_rows):
    w('INSERT INTO asset_transfer_requests (transfer_id, asset_id, from_office_id, to_office_id, to_personnel_id, to_location, reason, status, '
      'requested_by, requested_at, reviewed_by, reviewed_at, review_note) VALUES\n' + ',\n'.join(c) + ';')
for c in chunks(srows):
    w('INSERT INTO property_return_slips (slip_id, slip_number, transfer_id, asset_id, purpose, office_name, returned_by_id, returned_by_name, '
      'returned_by_position, return_date, property_number, par_number, description, specifications, unit_value, acquisition_date, created_by, created_at) VALUES\n'
      + ',\n'.join(c) + ';')
for c in chunks(prows):
    w('INSERT INTO asset_par_issuances (par_number, asset_id, transfer_id, return_slip_id, personnel_id, personnel_name, personnel_position, office_name, '
      'issue_date, property_number, description, specifications, unit_value, acquisition_date, is_original, created_by, created_at) VALUES\n' + ',\n'.join(c) + ';')
for c in chunks(mrows):
    w('INSERT INTO maintenance_ledger (maintenance_id, asset_id, maintenance_type, findings, actions_taken, assigned_to, maintenance_date, cost, status, '
      'recorded_by, created_at, updated_at, approval_status) VALUES\n' + ',\n'.join(c) + ';')
for c in chunks(mitems):
    w('INSERT INTO maintenance_items (maintenance_id, line_no, kind, particular, unit, quantity, unit_cost, total_cost) VALUES\n' + ',\n'.join(c) + ';')
for c in chunks(drows):
    w('INSERT INTO disposal_ledger (disposal_id, asset_id, reason, inspection_findings, recommended_method, disposal_status, inspection_date, approved_by, '
      'appraised_value, or_number, amount, recorded_by, created_at, updated_at, approval_status) VALUES\n' + ',\n'.join(c) + ';')
w('COMMIT;')

path = os.path.join(HERE, 'realistic_seed.sql')
with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(out) + '\n')

# summary
from collections import Counter
print(f'{len(assets)} assets, {len(hrows)} history entries, {len(mrows)} maintenance ({len(mitems)} lines), '
      f'{len(drows)} disposals, {len(trows)} transfers (+{len(pending_rows)} pending), {sum(len(v) for v in staff.values())} staff accounts')
print('by category:', dict(Counter(a['cat'] for a in assets)))
print('by condition:', dict(Counter(a['cond'] for a in assets)))
print('by lifecycle:', dict(Counter(lifecycle(a) for a in assets)))
print('wrote', path)
