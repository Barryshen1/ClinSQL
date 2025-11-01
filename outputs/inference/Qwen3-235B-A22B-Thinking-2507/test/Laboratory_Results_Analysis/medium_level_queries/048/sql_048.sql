WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 55 AND 65
),
ami_admissions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.subject_id = di.subject_id AND pa.hadm_id = di.hadm_id
  WHERE 
    di.seq_num = 1
    AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')
),
first_tnt AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS first_tnt_value,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    LOWER(dli.label) LIKE '%troponin t high sensitive%'
    AND le.valuenum IS NOT NULL
    AND LOWER(le.valueuom) = 'ng/ml'
),
qualifying_admissions AS (
  SELECT 
    aa.subject_id,
    aa.hadm_id,
    ft.first_tnt_value
  FROM ami_admissions aa
  INNER JOIN first_tnt ft
    ON aa.hadm_id = ft.hadm_id
  WHERE 
    ft.rn = 1
    AND ft.first_tnt_value > 0.01
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(first_tnt_value) AS mean_tnt,
  APPROX_QUANTILES(first_tnt_value, 1000)[OFFSET(500)] AS median_tnt,
  APPROX_QUANTILES(first_tnt_value, 1000)[OFFSET(750)] 
    - APPROX_QUANTILES(first_tnt_value, 1000)[OFFSET(250)] AS iqr_tnt
FROM qualifying_admissions;