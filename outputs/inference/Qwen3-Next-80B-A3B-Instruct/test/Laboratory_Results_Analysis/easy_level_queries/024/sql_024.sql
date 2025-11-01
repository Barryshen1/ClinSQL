WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE d_icd.icd_code IN (
    'A41.9', 'R65.20', 'R65.21', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.4', 'A40.5', 'A40.8', 'A40.9',
    'A41.0', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.6', 'A41.7', 'A41.8', 'A41.9'
  )
    AND d.icd_version = 10
),
platelet_earliest AS (
  SELECT 
    le.hadm_id,
    MIN(le.charttime) AS first_platelet_time
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
  GROUP BY le.hadm_id
),
platelet_values AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS platelet_count
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  INNER JOIN platelet_earliest pe ON le.hadm_id = pe.hadm_id AND le.charttime = pe.first_platelet_time
  WHERE LOWER(dl.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
)
SELECT 
  STDDEV(p.platelet_count) AS sd_admission_platelet_count
FROM platelet_values p
INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.hadm_id = a.hadm_id
INNER JOIN physionet-data.mimiciv_3_1_hosp.patients pat ON a.subject_id = pat.subject_id
INNER JOIN sepsis_admissions sa ON p.hadm_id = sa.hadm_id
WHERE pat.gender = 'M';