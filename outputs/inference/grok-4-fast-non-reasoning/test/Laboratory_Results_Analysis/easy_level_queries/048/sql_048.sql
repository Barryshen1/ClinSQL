WITH copd_patients AS (
  -- Identify patients with COPD diagnosis (ICD-10 J44*)
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age >= 56
    AND di.icd_version = 10
    AND di.icd_code LIKE 'J44%'
),
creatinine_itemids AS (
  -- Identify serum creatinine itemids
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label = 'Creatinine'
    AND category = 'Chemistry'
    AND fluid IS NULL  -- Serum (not urine, etc.)
),
patient_creatinine_avg AS (
  -- Average creatinine per patient in first 24h of admissions
  SELECT 
    cp.subject_id,
    AVG(le.valuenum) AS avg_creatinine
  FROM copd_patients cp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON cp.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id 
    AND a.hadm_id = le.hadm_id
  INNER JOIN creatinine_itemids ci
    ON le.itemid = ci.itemid
  WHERE le.valuenum IS NOT NULL 
    AND le.valuenum > 0
    AND le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
  GROUP BY cp.subject_id
  HAVING avg_creatinine IS NOT NULL  -- Ensure valid average
)
-- Compute 75th percentile across patients
SELECT 
  PERCENTILE_CONT(avg_creatinine, 0.75) AS p75_avg_creatinine
FROM patient_creatinine_avg;