WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 50 AND 60
),
dx_filtered AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.age_at_admission
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses ddx
    ON di.icd_code = ddx.icd_code AND di.icd_version = ddx.icd_version
  WHERE LOWER(ddx.long_title) LIKE '%chest pain%'
     OR LOWER(ddx.long_title) LIKE '%myocardial infarction%'
     OR LOWER(ddx.long_title) LIKE '%acute mi%'
     OR LOWER(ddx.long_title) LIKE '%ami%'
),
lab_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) LIKE '%troponin%t%'
    AND LOWER(label) NOT LIKE '%calcium%'
    AND LOWER(label) NOT LIKE '%troponin i%'
),
first_tnt AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN lab_items li ON le.itemid = li.itemid
  WHERE le.valuenum IS NOT NULL
),
initial_tnt_above_uln AS (
  SELECT 
    dx.subject_id,
    dx.hadm_id,
    ft.valuenum AS initial_tnt
  FROM dx_filtered dx
  INNER JOIN first_tnt ft
    ON dx.hadm_id = ft.hadm_id
  WHERE ft.rn = 1
    AND ft.valuenum > 0.014
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(initial_tnt) AS mean_initial_tnt,
  APPROX_QUANTILES(initial_tnt, 100)[OFFSET(50)] AS median_initial_tnt,
  APPROX_QUANTILES(initial_tnt, 100)[OFFSET(25)] AS q1_initial_tnt,
  APPROX_QUANTILES(initial_tnt, 100)[OFFSET(75)] AS q3_initial_tnt
FROM initial_tnt_above_uln;