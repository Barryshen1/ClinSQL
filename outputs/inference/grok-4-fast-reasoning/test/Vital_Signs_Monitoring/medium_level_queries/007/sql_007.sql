WITH eligible_stays AS (
  SELECT i.stay_id, i.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 80
    AND p.anchor_age <= 90
),
avg_spo2_per_stay AS (
  SELECT 
    s.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM eligible_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = s.subject_id
    AND ce.stay_id = s.stay_id
  WHERE ce.itemid = 220277
    AND ce.valuenum IS NOT NULL
  GROUP BY s.stay_id
  HAVING avg_spo2 IS NOT NULL
)
SELECT 
  (COUNTIF(avg_spo2 <= 88) * 100.0 / COUNT(*)) AS percentile
FROM avg_spo2_per_stay;