WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND diag.icd_version = 10
    AND diag.seq_num = 1  -- primary diagnosis
    AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I20%')  -- ACS codes
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS initial_troponin,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN acs_admissions aa
    ON le.hadm_id = aa.hadm_id
  WHERE le.itemid = 51137  -- hs-Troponin T
    AND le.valuenum > 0.014  -- above 99th percentile URL
    AND le.valuenum IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(initial_troponin, 100)[OFFSET(50)] AS median_initial_troponin,
  APPROX_QUANTILES(initial_troponin, 100)[OFFSET(25)] AS q1_initial_troponin,
  APPROX_QUANTILES(initial_troponin, 100)[OFFSET(75)] AS q3_initial_troponin
FROM first_troponin
WHERE rn = 1;