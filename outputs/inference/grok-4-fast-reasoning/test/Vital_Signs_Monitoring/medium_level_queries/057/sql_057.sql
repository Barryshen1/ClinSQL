WITH qualifying_stays AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 85 AND 95
),
avgs AS (
  SELECT 
    c.stay_id,
    AVG(
      CASE 
        WHEN c.valueuom = 'F' THEN (c.valuenum - 32) * 5.0 / 9 
        ELSE c.valuenum 
      END
    ) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN qualifying_stays qs 
    ON c.stay_id = qs.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON c.itemid = di.itemid
  WHERE di.category = 'Temperature'
    AND c.valuenum IS NOT NULL
    AND c.valueuom IN ('C', 'F')
  GROUP BY c.stay_id
  HAVING COUNT(*) >= 1  -- At least one valid measurement
)
SELECT 
  COUNT(*) AS total_stays_with_temps,
  COUNTIF(avg_temp <= 36.0) AS num_stays_le_36,
  ROUND(SAFE_DIVIDE(COUNTIF(avg_temp <= 36.0) * 100.0, COUNT(*)), 2) AS percentile_rank
FROM avgs;