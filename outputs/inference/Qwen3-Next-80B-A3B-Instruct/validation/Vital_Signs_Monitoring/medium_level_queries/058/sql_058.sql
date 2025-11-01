WITH female_icu_ages AS (
  SELECT i.stay_id, i.intime, p.anchor_age
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
sbp_measurements AS (
  SELECT 
    f.stay_id,
    c.valuenum
  FROM female_icu_ages f
  JOIN physionet-data.mimiciv_3_1_icu.chartevents c
    ON f.stay_id = c.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE d.label IN ('Systolic BP', 'Arterial BP Systolic', 'BP Systolic')
    AND c.charttime >= f.intime
    AND c.charttime < f.intime + INTERVAL 24 HOUR
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 50 AND 250
),
per_stay_avg AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_sbp_24h
  FROM sbp_measurements
  GROUP BY stay_id
  HAVING AVG(valuenum) IS NOT NULL
)
SELECT 
  100.0 * SUM(CASE WHEN avg_sbp_24h <= 120 THEN 1 ELSE 0 END) / COUNT(*) AS percentile
FROM per_stay_avg;