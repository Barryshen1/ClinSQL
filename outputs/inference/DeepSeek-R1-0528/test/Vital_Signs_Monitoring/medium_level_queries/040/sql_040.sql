WITH eligible_stays AS (
  SELECT 
    ie.stay_id,
    ie.intime,
    ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = ie.stay_id
        AND pe.itemid = 227287  -- High-flow nasal cannula
    )
),
per_stay_sbp AS (
  SELECT 
    e.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM eligible_stays e
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON e.stay_id = ce.stay_id
    AND ce.charttime >= e.intime
    AND ce.charttime <= e.outtime
  WHERE ce.itemid IN (220045, 220050)  -- SBP measurements
    AND ce.valuenum IS NOT NULL
  GROUP BY e.stay_id
)
SELECT 
  MIN(mean_sbp) AS min_mean_sbp
FROM per_stay_sbp;