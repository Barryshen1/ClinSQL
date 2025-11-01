WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(a.admission_type) = 'emergency'
    AND (a.dischtime IS NOT NULL OR a.deathtime IS NOT NULL)
),
cohort_los AS (
  SELECT
    c.*,
    TIMESTAMP_DIFF(COALESCE(c.dischtime, c.deathtime), c.admittime, DAY) AS los_days
  FROM cohort AS c
)
SELECT
  s.alive_total,
  s.died_total,
  s.alive_with_los_ge_7,
  s.died_with_los_ge_7,
  SAFE_DIVIDE(s.alive_with_los_ge_7, NULLIF(s.alive_total, 0)) AS alive_prop_los_ge_7,
  SAFE_DIVIDE(s.died_with_los_ge_7, NULLIF(s.died_total, 0)) AS died_prop_los_ge_7,
  pctl.pct_le_7_days
FROM (
  SELECT
    SUM(CASE WHEN deathtime IS NULL THEN 1 ELSE 0 END) AS alive_total,
    SUM(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END) AS died_total,
    SUM(CASE WHEN deathtime IS NULL AND los_days >= 7 THEN 1 ELSE 0 END) AS alive_with_los_ge_7,
    SUM(CASE WHEN deathtime IS NOT NULL AND los_days >= 7 THEN 1 ELSE 0 END) AS died_with_los_ge_7
  FROM cohort_los
) AS s
CROSS JOIN (
  SELECT 100.0 * COUNTIF(los_days <= 7) / NULLIF(COUNT(*), 0) AS pct_le_7_days
  FROM cohort_los
) AS pctl;