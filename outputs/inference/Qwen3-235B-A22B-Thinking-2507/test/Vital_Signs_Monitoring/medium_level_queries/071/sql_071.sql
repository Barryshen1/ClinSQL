WITH filtered_stays AS (
  SELECT 
    s.stay_id,
    EXTRACT(YEAR FROM s.intime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM s.intime) - (p.anchor_year - p.anchor_age) BETWEEN 38 AND 48
),
spo2_per_stay AS (
  SELECT 
    s.stay_id,
    AVG(c.valuenum) AS mean_spo2
  FROM filtered_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  WHERE c.itemid = 220277  -- Standard SpO2 itemid in MIMIC-IV
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 0 AND 100  -- Valid SpO2 range
  GROUP BY s.stay_id
  HAVING COUNT(c.valuenum) > 0  -- Ensure at least one measurement
)
SELECT 
  (COUNTIF(mean_spo2 <= 92) * 100.0) / COUNT(*) AS percentile_rank
FROM spo2_per_stay;