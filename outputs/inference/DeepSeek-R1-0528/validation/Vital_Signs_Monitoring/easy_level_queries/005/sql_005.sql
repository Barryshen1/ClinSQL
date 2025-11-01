WITH filtered_patients AS (
  SELECT 
    subject_id, 
    anchor_year - anchor_age AS birth_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
sbp_events AS (
  SELECT 
    ce.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_patients p
    ON ce.subject_id = p.subject_id
  WHERE 
    ce.itemid IN (220050, 220179)  -- Systolic BP item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 300  -- Valid SBP range
    AND EXTRACT(YEAR FROM ce.charttime) - p.birth_year BETWEEN 59 AND 69
)
SELECT 
  APPROX_QUANTILES(sbp, 100)[OFFSET(75)] AS sbp_75th_percentile
FROM sbp_events;