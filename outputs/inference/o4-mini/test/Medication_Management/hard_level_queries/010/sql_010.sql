WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
),
med_complexity AS (
  SELECT
    pr.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    JOIN cohort AS c
      ON pr.hadm_id = c.hadm_id
  WHERE
    pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    pr.hadm_id
),
with_scores AS (
  SELECT
    c.*,
    COALESCE(mc.complexity_score, 0) AS complexity_score,
    -- Compute hospital length of stay in days
    DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) AS los_days,
    -- 30-day readmission indicator
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE
        a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30d,
    c.hospital_expire_flag AS died_in_hosp
  FROM
    cohort AS c
    LEFT JOIN med_complexity AS mc
      ON c.hadm_id = mc.hadm_id
),
with_quintile AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY complexity_score) AS complexity_quintile
  FROM
    with_scores
)
SELECT
  complexity_quintile,
  COUNT(*) AS num_patients,
  ROUND(AVG(complexity_score), 2) AS mean_complexity_score,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(died_in_hosp), 3) AS in_hospital_mortality_rate,
  ROUND(AVG(CAST(readmit_30d AS INT64)), 3) AS readmission_30d_rate
FROM
  with_quintile
GROUP BY
  complexity_quintile
ORDER BY
  complexity_quintile;