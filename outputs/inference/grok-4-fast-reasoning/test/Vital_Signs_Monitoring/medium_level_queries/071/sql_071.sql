WITH stays AS (
  SELECT 
    i.stay_id,
    p.gender,
    EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND 38 <= (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age)
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) <= 48
),
spo2_means AS (
  SELECT 
    s.stay_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = s.stay_id
  WHERE ce.itemid = 220277 
    AND ce.valuenum IS NOT NULL
  GROUP BY s.stay_id
)
SELECT 
  COUNTIF(mean_spo2 <= 92) * 1.0 / COUNT(*) AS proportion_le_92
FROM spo2_means;