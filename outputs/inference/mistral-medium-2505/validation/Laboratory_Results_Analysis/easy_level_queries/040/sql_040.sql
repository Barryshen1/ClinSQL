WITH
-- Define DKA ICD-10 codes (comprehensive list)
dka_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND icd_code IN (
      'E13.10', 'E13.11', 'E10.10', 'E10.11', 'E11.10', 'E11.11',
      'E13.65', 'E10.65', 'E11.65', 'E13.64', 'E10.64', 'E11.64'
    )
),

-- Get admissions with DKA diagnosis for female patients aged 58 at admission
dka_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  JOIN dka_icd_codes dka ON d.icd_code = dka.icd_code
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) = 58
),

-- Get serum glucose itemids (specific to serum glucose)
glucose_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE itemid IN (50809, 50931, 50804, 50805, 50806, 50807, 50808, 50810, 50811, 50812, 50813, 50814, 50815, 50816, 50817, 50818, 50819, 50820, 50821, 50822, 50823, 50824, 50825, 50826, 50827, 50828, 50829, 50830, 50831, 50832, 50833, 50834, 50835, 50836, 50837, 50838, 50839, 50840, 50841, 50842, 50843, 50844, 50845, 50846, 50847, 50848, 50849, 50850, 50851, 50852, 50853, 50854, 50855, 50856, 50857, 50858, 50859, 50860, 50861, 50862, 50863, 50864, 50865, 50866, 50867, 50868, 50869, 50870, 50871, 50872, 50873, 50874, 50875, 50876, 50877, 50878, 50879, 50880, 50881, 50882, 50883, 50884, 50885, 50886, 50887, 50888, 50889, 50890, 50891, 50892, 50893, 50894, 50895, 50896, 50897, 50898, 50899, 50900, 50901, 50902, 50903, 50904, 50905, 50906, 50907, 50908, 50909, 50910, 50911, 50912, 50913, 50914, 50915, 50916, 50917, 50918, 50919, 50920, 50921, 50922, 50923, 50924, 50925, 50926, 50927, 50928, 50929, 50930, 50931, 50932, 50933, 50934, 50935, 50936, 50937, 50938, 50939, 50940, 50941, 50942, 50943, 50944, 50945, 50946, 50947, 50948, 50949, 50950, 50951, 50952, 50953, 50954, 50955, 50956, 50957, 50958, 50959, 50960, 50961, 50962, 50963, 50964, 50965, 50966, 50967, 50968, 50969, 50970, 50971, 50972, 50973, 50974, 50975, 50976, 50977, 50978, 50979, 50980, 50981, 50982, 50983, 50984, 50985, 50986, 50987, 50988, 50989, 50990, 50991, 50992, 50993, 50994, 50995, 50996, 50997, 50998, 50999)
),

-- Get peak glucose per admission
peak_glucose_per_admission AS (
  SELECT
    le.hadm_id,
    MAX(le.valuenum) AS peak_glucose
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN glucose_itemids gi ON le.itemid = gi.itemid
  JOIN dka_admissions da ON le.hadm_id = da.hadm_id
  WHERE le.charttime BETWEEN da.admittime AND da.dischtime
  GROUP BY le.hadm_id
)

-- Calculate median peak glucose
SELECT
  PERCENTILE_CONT(peak_glucose, 0.5) AS median_peak_glucose
FROM peak_glucose_per_admission;