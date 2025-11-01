WITH qualifying_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag 
    ON d.icd_code = diag.icd_code 
    AND d.icd_version = diag.icd_version
  WHERE p.gender = 'M'
    AND CAST(p.anchor_age AS INT64) = 61
    AND LOWER(diag.long_title) LIKE '%pneumonia%'
),
nadirs AS (
  SELECT 
    MIN(l.valuenum) AS nadir_cr
  FROM qualifying_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON qa.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON l.hadm_id = a.hadm_id 
    AND l.subject_id = a.subject_id
  WHERE l.itemid = 50912
    AND l.valuenum IS NOT NULL
    AND l.charttime >= a.admittime
    AND l.charttime <= a.dischtime
  GROUP BY qa.hadm_id
  HAVING nadir_cr IS NOT NULL
)
SELECT 
  (APPROX_QUANTILES(nadir_cr, 100)[OFFSET(75)] - 
   APPROX_QUANTILES(nadir_cr, 100)[OFFSET(25)]) AS iqr_nadir_creatinine
FROM nadirs;