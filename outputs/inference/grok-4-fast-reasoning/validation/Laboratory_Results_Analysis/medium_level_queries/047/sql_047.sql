WITH acs_hadms AS (
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = '9' AND (di.icd_code LIKE '410.%' OR di.icd_code = '411.1'))
      OR
      (di.icd_version = '10' AND (di.icd_code = 'I20.0' OR di.icd_code LIKE 'I21.%'))
    )
),
initial_troponin AS (
  SELECT hadm_id, valuenum AS initial_trop
  FROM (
    SELECT hadm_id, valuenum, ref_range_upper, charttime,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE le.itemid = 3616
      AND le.valuenum IS NOT NULL
      AND le.valueuom = 'ng/mL'
  ) ranked
  WHERE rn = 1
    AND valuenum > COALESCE(ref_range_upper, 0.01)
),
cohort AS (
  SELECT ah.subject_id, ah.hadm_id, it.initial_trop
  FROM acs_hadms ah
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ah.subject_id = p.subject_id
  JOIN initial_troponin it ON ah.hadm_id = it.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(AVG(initial_trop), 4) AS mean_initial_troponin,
  APPROX_QUANTILES(initial_trop, 4)[OFFSET(2)] AS median_initial_troponin,
  APPROX_QUANTILES(initial_trop, 4)[OFFSET(3)] - APPROX_QUANTILES(initial_trop, 4)[OFFSET(1)] AS iqr_initial_troponin
FROM cohort;