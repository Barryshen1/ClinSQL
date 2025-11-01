WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 83 AND 93
),

ami_admissions AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.age_at_admission, pa.los_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%myocardial infarction%'
    AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%') -- I21: ST-elevation and non-ST-elevation MI
),

troponin_t_labitems AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) = 'troponin t'
),

first_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum AS first_trop_t
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN troponin_t_labitems t ON le.itemid = t.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valuenum > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),

ami_with_first_troponin AS (
  SELECT
    ami.subject_id,
    ami.age_at_admission,
    ami.los_days,
    ft.first_trop_t
  FROM ami_admissions ami
  INNER JOIN first_troponin ft ON ami.hadm_id = ft.hadm_id
  WHERE ft.first_trop_t > 0.014  -- above 99th percentile URL
)

SELECT
  COUNT(*) AS N,
  AVG(age_at_admission) AS mean_age,
  AVG(los_days) AS mean_los,
  AVG(first_trop_t) AS mean_initial_troponin_t,
  MIN(first_trop_t) AS min_initial_troponin_t,
  MAX(first_trop_t) AS max_initial_troponin_t
FROM ami_with_first_troponin;