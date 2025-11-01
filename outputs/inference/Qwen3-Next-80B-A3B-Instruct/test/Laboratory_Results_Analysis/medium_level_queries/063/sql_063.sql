WITH acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND did.icd_code IN (
      'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I24.0', 'I20.0'
    )
),
initial_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE dl.label = 'Troponin I'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.valuenum > 0.04  -- Exceeds 99th percentile ULN (clinical threshold)
)
SELECT 
  COUNT(*) AS count,
  AVG(valuenum) AS mean,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr
FROM initial_troponin it
JOIN acs_admissions aa ON it.hadm_id = aa.hadm_id
WHERE it.rn = 1;