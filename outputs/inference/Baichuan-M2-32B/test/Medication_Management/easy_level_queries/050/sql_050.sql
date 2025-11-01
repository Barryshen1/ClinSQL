WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
)
SELECT
  AVG(duration_days) AS avg_duration_days
FROM (
  SELECT
    TIMESTAMP_DIFF(
      COALESCE(p.stoptime, TIMESTAMP(c.dischtime), CURRENT_TIMESTAMP()),
      p.starttime,
      DAY
    ) AS duration_days
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id
    AND c.hadm_id = p.hadm_id
  WHERE (LOWER(p.drug) LIKE '%spironolactone%' OR LOWER(p.drug) LIKE '%eplerenone%')
    AND p.starttime >= c.admittime
    AND p.starttime <= COALESCE(TIMESTAMP(c.dischtime), CURRENT_TIMESTAMP())
);