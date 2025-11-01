WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
ventilated AS (
  SELECT
    c.*,
    a.hospital_expire_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
    AND c.hadm_id = a.hadm_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.subject_id = c.subject_id
      AND ce.hadm_id = c.hadm_id
      AND ce.stay_id = c.stay_id
      AND ce.itemid = 720
      AND ce.charttime >= c.intime
      AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
      AND ce.value IS NOT NULL
      AND ce.value != ''
  )
),
scores AS (
  SELECT
    v.subject_id,
    v.stay_id,
    v.hadm_id,
    v.intime,
    v.outtime,
    v.los,
    v.anchor_age,
    v.hospital_expire_flag,
    MAX(ce.valuenum) AS instability_score
  FROM ventilated v
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = v.subject_id
    AND ce.hadm_id = v.hadm_id
    AND ce.stay_id = v.stay_id
    AND ce.itemid = 190
    AND ce.charttime >= v.intime
    AND ce.charttime < TIMESTAMP_ADD(v.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    v.subject_id, v.stay_id, v.hadm_id, v.intime, v.outtime, v.los,
    v.anchor_age, v.hospital_expire_flag
  HAVING instability_score IS NOT NULL
),
percentile_calc AS (
  SELECT
    SAFE_DIVIDE(COUNTIF(instability_score <= 80) * 100.0, COUNT(*)) AS percentile_80
  FROM scores
),
decile AS (
  SELECT
    los,
    hospital_expire_flag,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile_group
  FROM scores
),
unstable_decile AS (
  SELECT
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate
  FROM decile
  WHERE decile_group = 1
)
SELECT
  p.percentile_80,
  u.avg_los,
  u.mortality_rate
FROM percentile_calc p
CROSS JOIN unstable_decile u;