WITH cohort AS (
  SELECT 
    i.stay_id,
    i.intime,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    -- Age filter (73-83)
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 73 AND 83
),

spo2_data AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS spo2
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    -- SpO2 item IDs
    ce.itemid IN (220277, 223835)
    AND ce.valuenum IS NOT NULL
    -- First 24 hours of ICU stay
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),

mean_spo2_per_stay AS (
  SELECT 
    stay_id,
    AVG(spo2) AS mean_spo2
  FROM spo2_data
  GROUP BY stay_id
)

SELECT 
  -- Percentile calculation for 92%
  COUNTIF(mean_spo2 <= 92.0) * 100.0 / COUNT(*) AS percentile
FROM mean_spo2_per_stay;