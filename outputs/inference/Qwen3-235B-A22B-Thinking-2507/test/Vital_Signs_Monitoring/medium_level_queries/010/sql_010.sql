WITH population_stays AS (
  SELECT 
    s.stay_id,
    AVG(c.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  WHERE 
    p.gender = 'F'
    AND c.itemid IN (220050, 220179)  -- Systolic BP item IDs
    AND c.charttime >= s.intime
    AND c.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND c.valuenum > 0  -- Exclude invalid non-positive values
    AND (p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year)) BETWEEN 77 AND 87
  GROUP BY s.stay_id
)
SELECT 
  (COUNTIF(avg_sbp <= 160) * 100.0) / COUNT(*) AS percentile
FROM population_stays;