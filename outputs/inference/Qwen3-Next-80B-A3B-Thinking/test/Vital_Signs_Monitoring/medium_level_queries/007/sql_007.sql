WITH filtered_stays AS (
  SELECT 
    i.stay_id,
    p.anchor_age,
    p.anchor_year,
    i.intime,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 80 AND 90
),
avg_spo2_per_stay AS (
  SELECT 
    f.stay_id,
    AVG(c.valuenum) AS avg_spo2
  FROM filtered_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.stay_id = c.stay_id
  WHERE c.itemid = 220277
    AND c.valuenum IS NOT NULL
  GROUP BY f.stay_id
)
SELECT 
  SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile
FROM avg_spo2_per_stay;