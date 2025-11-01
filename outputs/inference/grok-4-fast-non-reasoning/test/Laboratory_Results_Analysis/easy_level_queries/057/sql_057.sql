WITH patient AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age = 61
),
pneumonia_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN patient p
    ON a.subject_id = p.subject_id
  WHERE (di.icd_code LIKE 'J%' OR di.icd_code = '486')  -- Pneumonia ICD-10 (J..) or ICD-9 (486)
),
creatinine_labs AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.charttime, 
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN pneumonia_admissions pa
    ON le.subject_id = pa.subject_id AND le.hadm_id = pa.hadm_id
  WHERE dli.label LIKE '%Creatinine%' 
    AND dli.category = 'Chemistry'
    AND le.valuenum IS NOT NULL
    AND le.valuenum BETWEEN 0.1 AND 10  -- Reasonable range for serum Cr (mg/dL)
),
nadirs AS (
  SELECT 
    cl.hadm_id,
    MIN(cl.valuenum) AS nadir_creatinine
  FROM creatinine_labs cl
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON cl.hadm_id = a.hadm_id
  WHERE cl.charttime >= a.admittime 
    AND cl.charttime <= a.dischtime
  GROUP BY cl.hadm_id
)
SELECT 
  PERCENTILE_CONT(nadir_creatinine, 0.75) OVER() - PERCENTILE_CONT(nadir_creatinine, 0.25) OVER() AS iqr_nadir_creatinine
FROM nadirs;