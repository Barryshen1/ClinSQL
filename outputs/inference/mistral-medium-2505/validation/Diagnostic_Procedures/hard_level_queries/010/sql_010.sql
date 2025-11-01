WITH
-- Get male patients aged 40-50 at admission
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
),

-- Get first ICU stay for each admission
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS icu_stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    patient_admissions pa
  ON
    i.subject_id = pa.subject_id AND i.hadm_id = pa.hadm_id
  WHERE
    i.intime IS NOT NULL
),

-- Identify patients with hemorrhagic stroke
hemorrhagic_stroke_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.icd_code LIKE '431.%' OR d.icd_code LIKE 'I61.%')
    AND di.long_title LIKE '%hemorrhagic%'
),

-- Count diagnostic procedures in first 72 hours of ICU stay
procedure_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count,
    MAX(CASE WHEN h.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS has_hemorrhagic_stroke
  FROM
    first_icu_stays f
  LEFT JOIN
    hemorrhagic_stroke_patients h
  ON
    f.subject_id = h.subject_id AND f.hadm_id = h.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  ON
    f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
    AND p.chartdate <= DATE_ADD(DATE(f.intime), INTERVAL 3 DAY)
  WHERE
    f.icu_stay_rank = 1  -- Only first ICU stay per admission
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Calculate percentiles and outcomes
final_results AS (
  SELECT
    has_hemorrhagic_stroke,
    COUNT(*) AS patient_count,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS percentile_90_procedures,
    AVG(f.los) AS avg_icu_los,
    SUM(CASE WHEN pa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN pa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM
    procedure_counts pc
  JOIN
    first_icu_stays f
  ON
    pc.stay_id = f.stay_id
  JOIN
    patient_admissions pa
  ON
    pc.subject_id = pa.subject_id AND pc.hadm_id = pa.hadm_id
  WHERE
    f.icu_stay_rank = 1
  GROUP BY
    has_hemorrhagic_stroke
)

SELECT
  CASE
    WHEN has_hemorrhagic_stroke = 1 THEN 'Hemorrhagic Stroke'
    ELSE 'Other Males 40-50'
  END AS patient_group,
  patient_count,
  percentile_90_procedures,
  avg_icu_los,
  in_hospital_deaths,
  mortality_rate
FROM
  final_results
ORDER BY
  has_hemorrhagic_stroke DESC;