WITH rr_data AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
    AND ce.itemid = 220210  -- Respiratory rate (breaths/min)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum <= 70  -- Reasonable range filter
    AND ce.charttime BETWEEN ie.intime 
        AND DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
  WHERE p.gender = 'M'
    AND DATETIME_DIFF(ie.intime, 
                      DATETIME(p.anchor_year, 1, 1),  -- Convert anchor_year to DATETIME (Jan 1 of that year)
                      YEAR) + p.anchor_age 
        BETWEEN 68 AND 78
  GROUP BY ie.stay_id
),
percentiles AS (
  SELECT 
    avg_rr,
    PERCENT_RANK() OVER (ORDER BY avg_rr) * 100 AS percentile_rank
  FROM rr_data
)
SELECT 
  percentile_rank
FROM percentiles
WHERE avg_rr = 12
LIMIT 1;