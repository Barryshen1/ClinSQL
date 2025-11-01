with initial_values AS (
  SELECT
    le.hadm_id,
    le.subject_id,
    le.charttime,
    le.valuenum,
    le.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON di.itemid = le.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = le.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON diag.subject_id = le.subject_id AND diag.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = diag.icd_code AND dd.icd_version = diag.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    -- Ischemic heart disease / myocardial infarction themes
    AND (LOWER(dd.long_title) LIKE '%ischemic%' OR LOWER(dd.long_title) LIKE '%myocardial infarction%')
    -- Troponin T hs test label variants (robust coverage)
    AND (
      LOWER(di.label) LIKE '%troponin t%' OR
      LOWER(di.label) LIKE '%troponin_t%' OR
      LOWER(di.label) LIKE '%hs troponin t%' OR
      LOWER(di.label) LIKE '%high sensitivity troponin t%' OR
      LOWER(di.label) LIKE '%hs_troponin t%' OR
      LOWER(di.label) LIKE '%troponin%hs%'
    )
    -- Valid numeric value and ULN context
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),
ordered AS (
  SELECT
    hadm_id,
    valuenum,
    charttime,
    ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM initial_values
),
first_measurements AS (
  -- Take the initial measurement per admission that is above ULN
  SELECT valuenum
  FROM ordered
  WHERE rn = 1
    AND valuenum > ref_range_upper
),
quantiles AS (
  SELECT APPROX_QUANTILES(valuenum, 4) AS q
  FROM first_measurements
)
SELECT
  q[OFFSET(0)] AS min_value,
  q[OFFSET(1)] AS p25,
  q[OFFSET(2)] AS p50,
  q[OFFSET(3)] AS p75,
  q[OFFSET(4)] AS max_value
FROM quantiles;