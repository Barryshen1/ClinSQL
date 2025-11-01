WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND diag.icd_version = 10
    AND diag.icd_code LIKE 'I2%'  -- ACS codes: I20-I25
),
first_troponin AS (
  SELECT 
    acs.subject_id,
    acs.hadm_id,
    MIN(le.charttime) AS first_charttime,
    le.valuenum AS troponin_value
  FROM acs_admissions acs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON acs.hadm_id = le.hadm_id
  WHERE le.itemid = 51003  -- Troponin I (quantitative)
    AND le.valuenum > 0.04  -- Exceeds 99th percentile ULN (0.04 ng/mL)
  GROUP BY acs.subject_id, acs.hadm_id, le.valuenum
)
SELECT
  COUNT(*) AS n_patients,
  AVG(troponin_value) AS mean_troponin,
  APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)] AS median_troponin,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS q1_troponin,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] AS q3_troponin
FROM first_troponin;