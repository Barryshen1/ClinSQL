WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 67 AND 77
),

acs_admissions AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%myocardial infarction%'
     OR LOWER(d.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(d.long_title) LIKE '%unstable angina%'
     OR (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code = 'I20.0')
),

troponin_t_values AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_t_value,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
    AND le.charttime IS NOT NULL
),

initial_troponin AS (
  SELECT 
    acs.subject_id,
    acs.hadm_id,
    tv.troponin_t_value
  FROM acs_admissions acs
  INNER JOIN troponin_t_values tv
    ON acs.hadm_id = tv.hadm_id
   AND tv.charttime >= acs.admittime
   AND tv.rn = 1  -- First (earliest) value in admission
  WHERE tv.troponin_t_value > 0.014  -- Above 99th percentile
)

SELECT
  COUNT(*) AS admission_count,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(troponin_t_value) AS mean_initial_troponin_t,
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(50)] AS median_initial_troponin_t,
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(25)] AS q1_initial_troponin_t,
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(75)] AS q3_initial_troponin_t
FROM initial_troponin;