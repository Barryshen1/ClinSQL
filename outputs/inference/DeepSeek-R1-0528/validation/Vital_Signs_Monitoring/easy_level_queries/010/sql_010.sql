WITH eligible_stays AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM ie.intime) - p.anchor_year BETWEEN 71 AND 81
),
dbp_events AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS dbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE 
    ce.itemid IN (220180, 225310)  -- DBP item IDs (non-invasive/invasive)
    AND ce.valuenum IS NOT NULL    -- Ensure numeric value exists
),
per_stay_max_dbp AS (
  SELECT 
    e.stay_id,
    MAX(d.dbp) AS max_dbp
  FROM eligible_stays e
  INNER JOIN dbp_events d 
    ON e.stay_id = d.stay_id
  GROUP BY e.stay_id
)
SELECT 
  APPROX_QUANTILES(max_dbp, 100)[OFFSET(50)] AS median_per_stay_max_dbp
FROM per_stay_max_dbp;