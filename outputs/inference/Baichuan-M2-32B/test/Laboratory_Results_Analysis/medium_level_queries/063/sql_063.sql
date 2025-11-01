WITH troponin_items AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin I%' 
    AND category = 'Cardiac'
),
patients_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 84 AND 94
),
acs_admissions AS (
  SELECT 
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
    AND icd_version = 10
    AND icd_code IN ('I20', 'I21', 'I22')
),
troponin_labs AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn_trop
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN troponin_items t 
    ON l.itemid = t.itemid
  INNER JOIN patients_admissions pa 
    ON l.subject_id = pa.subject_id AND l.hadm_id = pa.hadm_id
  WHERE l.valuenum IS NOT NULL
    AND l.valuenum > 0.04
    AND l.charttime BETWEEN pa.admittime AND pa.admittime + INTERVAL 24 HOUR
),
qualifying_admissions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    tl.valuenum AS initial_trop
  FROM patients_admissions pa
  INNER JOIN acs_admissions aa 
    ON pa.subject_id = aa.subject_id AND pa.hadm_id = aa.hadm_id
  INNER JOIN troponin_labs tl 
    ON pa.subject_id = tl.subject_id AND pa.hadm_id = tl.hadm_id AND tl.rn_trop = 1
),
first_admission_per_patient AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    initial_trop,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn_adm
  FROM qualifying_admissions
),
final_patients AS (
  SELECT 
    subject_id,
    hadm_id,
    initial_trop
  FROM first_admission_per_patient
  WHERE rn_adm = 1
)
SELECT 
  COUNT(*) AS patient_count,
  AVG(initial_trop) AS mean_trop,
  APPROX_QUANTILES(initial_trop, 100)[OFFSET(50)] AS median_trop,
  APPROX_QUANTILES(initial_trop, 100)[OFFSET(75)] - APPROX_QUANTILES(initial_trop, 100)[OFFSET(25)] AS iqr_trop
FROM final_patients;