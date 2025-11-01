WITH copd_admissions AS (
  -- admissions that have a COPD diagnosis (ICD-10 J44* or ICD-9 491*,492*,496*), or whose diagnosis description
  -- mentions COPD / obstructive pulmonary disease
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    -- ICD-10 COPD codes
    (d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'j44%')
    OR
    -- ICD-9 COPD-related codes
    (d.icd_version = 9 AND (
       LOWER(d.icd_code) LIKE '491%' OR LOWER(d.icd_code) LIKE '492%' OR LOWER(d.icd_code) LIKE '496%'
     ))
    OR
    -- fallback: description contains COPD / obstructive pulmonary
    LOWER(COALESCE(dd.long_title, '')) LIKE '%copd%'
    OR LOWER(COALESCE(dd.long_title, '')) LIKE '%obstructive pulmonary%'
  )
),

creatinine_items AS (
  -- lab itemids that look like serum creatinine
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
),

cohort_admissions AS (
  -- admissions for 90-year-old male patients that have COPD diagnoses
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN copd_admissions c
    ON a.hadm_id = c.hadm_id
  WHERE p.anchor_age = 90
    AND p.gender = 'M'
),

per_admission_avg_creat AS (
  -- compute per-admission average serum creatinine within first 24 hours
  SELECT
    ca.subject_id,
    ca.hadm_id,
    AVG(le.valuenum) AS avg_creatinine
  FROM cohort_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = ca.hadm_id
  JOIN creatinine_items di
    ON le.itemid = di.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= ca.admittime
    AND le.charttime <= TIMESTAMP_ADD(ca.admittime, INTERVAL 24 HOUR)
  GROUP BY ca.subject_id, ca.hadm_id
  HAVING COUNT(*) >= 1
)

-- final: standard deviation across per-admission average creatinines
SELECT
  COUNT(*) AS n_admissions,
  ROUND(STDDEV_SAMP(avg_creatinine), 4) AS sd_of_avg_creatinine_mg_per_dL
FROM per_admission_avg_creat;