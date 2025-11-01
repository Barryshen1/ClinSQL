WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),

-- 2) Compute per-stay average temperature for eligible ICU stays
per_stay AS (
  SELECT i.stay_id,
         AVG(ce.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id  = i.hadm_id
   AND ce.stay_id  = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE i.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND di.label LIKE '%temperature%'
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.outtime
    AND ce.valuenum IS NOT NULL
  GROUP BY i.stay_id
)

-- 3) Calculate the percentile rank for 36.0°C within the distribution
SELECT
  100.0 * SUM(CASE WHEN avg_temp <= 36.0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS percentile_rank_36C
FROM per_stay;