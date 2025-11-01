WITH sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
     OR LOWER(label) LIKE '%sbp%'
),

-- Per-stay mean SBP within first 48 hours for the cohort
per_stay_sbp AS (
  SELECT
    i.subject_id,
    i.stay_id,
    AVG(ch.valuenum) AS mean_sbp_48h
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ch
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON ch.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN sbp_items AS s
    ON ch.itemid = s.itemid
  WHERE ch.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
  GROUP BY i.subject_id, i.stay_id
  HAVING COUNT(*) > 0
)

-- Compute the percentile of 150 within the distribution
SELECT
  100.0 * SUM(CASE WHEN mean_sbp_48h <= 150 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS percentile_150_in_group
FROM per_stay_sbp;