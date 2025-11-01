WITH cohort AS (
  SELECT 
    p.subject_id,
    ie.stay_id,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON p.subject_id = ie.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) BETWEEN 51 AND 61
),
first_rr AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS first_resp_rate
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.itemid = 220210  -- Respiratory Rate
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) = 1
)
SELECT 
  STDDEV(first_resp_rate) AS sd_first_resp_rate
FROM first_rr;