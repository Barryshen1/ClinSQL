WITH
-- Get male patients aged 68-78
patient_base AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- Identify patients who received vasopressors within 72 hours of ICU admission
vasopressor_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.icu_intime
  FROM
    patient_base p
  JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` ie ON p.subject_id = ie.subject_id AND p.hadm_id = ie.hadm_id AND p.stay_id = ie.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE
    -- Common vasopressor itemids (norepinephrine, epinephrine, vasopressin, etc.)
    ie.itemid IN (221906, 221905, 221907, 221908, 221909, 221910, 221911, 221912, 221913, 221914, 221915, 221916, 221917, 221918, 221919, 221920, 221921, 221922, 221923, 221924, 221925, 221926, 221927, 221928, 221929, 221930, 221931, 221932, 221933, 221934, 221935, 221936, 221937, 221938, 221939, 221940, 221941, 221942, 221943, 221944, 221945, 221946, 221947, 221948, 221949, 221950, 221951, 221952, 221953, 221954, 221955, 221956, 221957, 221958, 221959, 221960, 221961, 221962, 221963, 221964, 221965, 221966, 221967, 221968, 221969, 221970, 221971, 221972, 221973, 221974, 221975, 221976, 221977, 221978, 221979, 221980, 221981, 221982, 221983, 221984, 221985, 221986, 221987, 221988, 221989, 221990, 221991, 221992, 221993, 221994, 221995, 221996, 221997, 221998, 221999)
    AND ie.starttime BETWEEN p.icu_intime AND TIMESTAMP_ADD(p.icu_intime, INTERVAL 72 HOUR)
),

-- Calculate diagnostic load (labs + imaging) within 72 hours of ICU admission
diagnostic_load AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    COUNT(DISTINCT le.labevent_id) AS lab_count,
    COUNT(DISTINCT he.seq_num) AS imaging_count,
    COUNT(DISTINCT le.labevent_id) + COUNT(DISTINCT he.seq_num) AS total_diagnostic_load
  FROM
    vasopressor_patients v
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le ON v.subject_id = le.subject_id AND v.hadm_id = le.hadm_id
    AND le.charttime BETWEEN v.icu_intime AND TIMESTAMP_ADD(v.icu_intime, INTERVAL 72 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he ON v.subject_id = he.subject_id AND v.hadm_id = he.hadm_id
    AND he.chartdate BETWEEN DATE(v.icu_intime) AND DATE(TIMESTAMP_ADD(v.icu_intime, INTERVAL 72 HOUR))
    AND he.short_description LIKE '%radiology%'
  GROUP BY
    v.subject_id, v.hadm_id, v.stay_id
),

-- Calculate quartiles for diagnostic load
diagnostic_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    total_diagnostic_load,
    NTILE(4) OVER (ORDER BY total_diagnostic_load) AS diagnostic_quartile
  FROM
    diagnostic_load
),

-- Calculate outcomes
outcomes AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    d.diagnostic_quartile,
    COUNT(DISTINCT pi.icd_code) AS procedure_count,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los_hours,
    a.hospital_expire_flag,
    -- Check for readmission within 30 days
    MAX(CASE
      WHEN a2.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30day
  FROM
    diagnostic_quartiles d
  JOIN
    patient_base p ON d.subject_id = p.subject_id AND d.hadm_id = p.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON d.subject_id = pi.subject_id AND d.hadm_id = pi.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a2.subject_id = d.subject_id
    AND a2.admittime > a.dischtime
    AND a2.admittime < TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
  GROUP BY
    d.subject_id, d.hadm_id, d.stay_id, d.diagnostic_quartile, a.hospital_expire_flag, a.dischtime, a.admittime
)

-- Final aggregation by quartile
SELECT
  diagnostic_quartile,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(hospital_los_hours) AS avg_hospital_los_hours,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate,
  AVG(readmitted_30day) AS readmission_30day_rate
FROM
  outcomes
GROUP BY
  diagnostic_quartile
ORDER BY
  diagnostic_quartile;