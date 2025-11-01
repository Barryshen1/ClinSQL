WITH base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.gender,
    p.anchor_age,
    a.edregtime,
    a.edouttime,
    CASE
      WHEN a.deathtime IS NOT NULL THEN 'Died'
      ELSE 'Alive'
    END AS discharge_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (UPPER(p.gender) = 'M' OR UPPER(p.gender) = 'MALE')
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.edregtime IS NOT NULL
    AND (a.dischtime IS NOT NULL OR a.deathtime IS NOT NULL)
)

SELECT
  discharge_status,
  COUNT(*) AS npatients,
  CAST(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS FLOAT64) / COUNT(*) AS pct_ge7_days,
  CAST(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS FLOAT64) / COUNT(*) AS pct_ge14_days,
  CAST(SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS FLOAT64) / COUNT(*) AS pct_leq10_days
FROM (
  SELECT t.*,
         TIMESTAMP_DIFF(IFNULL(t.dischtime, t.deathtime), t.admittime, DAY) AS los_days
  FROM base t
) AS sub
GROUP BY discharge_status
ORDER BY discharge_status;