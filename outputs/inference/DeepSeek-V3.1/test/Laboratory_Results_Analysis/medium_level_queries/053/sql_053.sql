WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code = 'I20.0'
),
first_troponin AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label LIKE '%troponin i%' 
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0.04
)
SELECT 
  COUNT(DISTINCT p.subject_id) AS patient_count,
  COUNT(DISTINCT aa.hadm_id) AS admission_count,
  ROUND(AVG(ft.troponin_value), 3) AS mean_troponin,
  ROUND(STDDEV(ft.troponin_value), 3) AS sd_troponin,
  MIN(ft.troponin_value) AS min_troponin,
  MAX(ft.troponin_value) AS max_troponin
FROM acs_admissions aa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON aa.subject_id = p.subject_id
INNER JOIN first_troponin ft
  ON aa.hadm_id = ft.hadm_id AND aa.subject_id = ft.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 68 AND 78
  AND ft.rn = 1;