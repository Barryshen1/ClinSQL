WITH acs_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 67 AND 77
    AND (d.icd_code LIKE 'I21%' OR d.icd_code = 'I20.0')
),
first_troponin AS (
  SELECT 
    acs.subject_id,
    acs.hadm_id,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY acs.hadm_id ORDER BY le.charttime) AS rn
  FROM acs_admissions acs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON acs.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.itemid IN (51003, 51004)  -- Troponin T items
    AND le.valuenum > 0.01  -- Above 99th percentile cutoff
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(troponin_value) AS mean_initial_troponin,
  APPROX_QUANTILES(troponin_value, 100)[50] AS median_initial_troponin,
  APPROX_QUANTILES(troponin_value, 100)[25] AS q1_initial_troponin,
  APPROX_QUANTILES(troponin_value, 100)[75] AS q3_initial_troponin
FROM first_troponin
WHERE rn = 1;