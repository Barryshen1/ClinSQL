WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 71 AND 81
),
max_dbp_per_stay AS (
  SELECT 
    ie.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN qualifying_patients qp 
    ON ie.subject_id = qp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ie.subject_id = ce.subject_id 
    AND ie.stay_id = ce.stay_id
  WHERE ce.itemid = 220180 
    AND ce.valuenum IS NOT NULL
  GROUP BY ie.stay_id
  HAVING max_dbp IS NOT NULL  -- Ensure only stays with valid max
)
SELECT 
  APPROX_QUANTILES(max_dbp, 2)[OFFSET(1)] AS median_max_dbp
FROM max_dbp_per_stay;