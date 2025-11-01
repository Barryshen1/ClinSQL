WITH spo2_items AS (
  -- identify likely SpO2 / oxygen saturation itemids by text match
  SELECT itemid, label, abbreviation
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (
        LOWER(label) LIKE '%spo2%'
     OR LOWER(label) LIKE '%o2 sat%'
     OR LOWER(label) LIKE '%o2saturation%'
     OR LOWER(label) LIKE '%oxygen saturation%'
     OR LOWER(label) LIKE '%o2 saturation%'
     OR LOWER(label) LIKE '%oxyhemoglobin saturation%'
  )
  OR (
     abbreviation IS NOT NULL
     AND (
       LOWER(abbreviation) LIKE '%spo2%'
       OR LOWER(abbreviation) LIKE '%o2%'
     )
  )
),

per_stay_means AS (
  -- compute mean SpO2 for each ICU stay over the first 24 hours
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    p.anchor_age,
    p.gender,
    AVG(c.valuenum) AS mean_spo2,
    COUNT(*) AS n_measures
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = s.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.subject_id = s.subject_id
   AND c.hadm_id = s.hadm_id
   AND c.stay_id = s.stay_id
  JOIN spo2_items d
    ON d.itemid = c.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    -- first 24 hours of the ICU stay
    AND c.charttime >= s.intime
    AND c.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    -- numeric measurements only and plausible SpO2 range
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 50 AND 100
  GROUP BY s.subject_id, s.hadm_id, s.stay_id, p.anchor_age, p.gender
  HAVING COUNT(*) >= 1
)

-- compute percentile of a target mean_spo2 = 92 among the distribution
SELECT
  92.0 AS target_mean_spo2,
  COUNTIF(mean_spo2 < 92.0) AS num_stays_less,
  COUNTIF(mean_spo2 = 92.0) AS num_stays_equal,
  COUNT(*) AS total_stays,
  100.0 * (COUNTIF(mean_spo2 < 92.0) + 0.5 * COUNTIF(mean_spo2 = 92.0)) / COUNT(*) AS percentile_of_92
FROM per_stay_means;