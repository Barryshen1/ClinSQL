WITH eligible AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
),
aged AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.anchor_age,
    e.anchor_year,
    (e.anchor_age + (EXTRACT(YEAR FROM e.admittime) - e.anchor_year)) AS age_at_adm
  FROM eligible AS e
  WHERE (e.anchor_age + (EXTRACT(YEAR FROM e.admittime) - e.anchor_year)) BETWEEN 42 AND 52
),
amiodarone_durations AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    CAST(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) AS FLOAT64) / 3600.0 AS duration_hours
  FROM aged AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = a.subject_id
   AND pr.hadm_id = a.hadm_id
  WHERE LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)
SELECT
  PERCENTILE_CONT(duration_hours, 0.25) OVER () AS percentile_25_hours
FROM amiodarone_durations
LIMIT 1;