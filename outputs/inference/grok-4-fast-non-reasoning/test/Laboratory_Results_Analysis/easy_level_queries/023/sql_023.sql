WITH sepsis_admissions AS (
  SELECT DISTINCT 
    ad.subject_id,
    ad.hadm_id,
    ad.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON p.subject_id = ad.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND (
      -- ICD-10 sepsis codes
      (diag.icd_version = '10' AND diag.icd_code LIKE 'A41%') OR
      -- ICD-9 sepsis codes
      (diag.icd_version = '9' AND (
        diag.icd_code LIKE '038%' OR
        diag.icd_code = '99591' OR
        diag.icd_code = '78552'
      ))
    )
),
lactate_measurements AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%lactate%'
    AND dli.category = 'Chemistry'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
)
SELECT 
  PERCENTILE_CONT(0.75, valuenum) - PERCENTILE_CONT(0.25, valuenum) AS iqr_serum_lactate
FROM lactate_measurements lm
INNER JOIN sepsis_admissions sa
  ON lm.subject_id = sa.subject_id
  AND lm.hadm_id = sa.hadm_id
WHERE DATE(lm.charttime) = DATE(TIMESTAMP(sa.dischtime));