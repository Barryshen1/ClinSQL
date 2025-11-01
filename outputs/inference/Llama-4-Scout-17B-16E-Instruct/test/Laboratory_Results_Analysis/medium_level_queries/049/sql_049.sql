WITH 
-- Define Troponin T itemid and ULN
troponin_t AS (
  SELECT itemid, label, ref_range_upper 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Troponin T%'
),

-- Get patients with Troponin T measurements
troponin_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, 
         le.valuenum AS troponin_value,
         tt.ref_range_upper AS uln
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON le.subject_id = p.subject_id
  JOIN troponin_t tt 
    ON le.itemid = tt.itemid
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 49 AND 59
    AND le.valuenum > 0  -- Assuming valuenum is used for numeric values
),

-- Filter for cohort with elevated Troponin T
cohort AS (
  SELECT troponin_value, uln
  FROM troponin_patients
  WHERE troponin_value > uln
)

-- Calculate and report statistics
SELECT 
  COUNT(*) AS cohort_size,
  APPROX_QUANTILES(uln, 100)[99] AS uln,
  APPROX_QUANTILES(troponin_value, 100)[25] AS p25,
  APPROX_QUANTILES(troponin_value, 100)[50] AS p50,
  APPROX_QUANTILES(troponin_value, 100)[75] AS p75,
  MIN(troponin_value) AS min_value,
  MAX(troponin_value) AS max_value
FROM cohort;