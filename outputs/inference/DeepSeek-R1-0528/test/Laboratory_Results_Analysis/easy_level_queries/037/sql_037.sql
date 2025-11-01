WITH sepsis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
    AND adm.subject_id = diag.subject_id
  WHERE 
    pat.gender = 'M'
    AND (
      (diag.icd_version = 9 AND 
        (diag.icd_code LIKE '038%' OR diag.icd_code IN ('995.91', '995.92', '785.52'))
      )
      OR
      (diag.icd_version = 10 AND 
        (diag.icd_code LIKE 'A40%' OR diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R65.2%')
      )
    )
),
platelet_peaks AS (
  SELECT sa.hadm_id, MAX(le.valuenum) AS peak_platelet
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
    AND sa.subject_id = le.subject_id
  WHERE le.itemid = 51265
    AND le.valuenum IS NOT NULL
  GROUP BY sa.hadm_id
)
SELECT 
  APPROX_QUANTILES(peak_platelet, 100)[OFFSET(75)] AS percentile_75_peak_platelet
FROM platelet_peaks;