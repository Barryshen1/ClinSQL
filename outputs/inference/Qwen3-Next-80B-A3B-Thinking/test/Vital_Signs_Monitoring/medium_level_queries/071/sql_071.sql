WITH filtered_stays AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
spoo2_means AS (
  SELECT 
    i.stay_id,
    AVG(c.valuenum) AS mean_spo2
  FROM filtered_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE c.itemid = 220277
    AND c.valuenum IS NOT NULL
  GROUP BY i.stay_id
)
SELECT 
  SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile
FROM spoo2_means;