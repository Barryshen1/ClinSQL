WITH systolic_ids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic blood pressure%'
),
female_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
per_stay_avg AS (
  SELECT
    f.stay_id,
    AVG(c.valuenum) AS avg_systolic
  FROM female_icustays AS f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON f.subject_id = c.subject_id
   AND f.hadm_id    = c.hadm_id
   AND f.stay_id    = c.stay_id
  JOIN systolic_ids AS s
    ON c.itemid = s.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.charttime BETWEEN f.intime
                       AND TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY f.stay_id
),
counts AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_systolic <= 130 THEN 1 ELSE 0 END) AS stays_le_130
  FROM per_stay_avg
)
SELECT
  stays_le_130,
  total_stays,
  SAFE_DIVIDE(stays_le_130, total_stays) * 100 AS percentile_of_130
FROM counts;