WITH base AS (
  SELECT
    i.los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'home'
      ELSE 'facility'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.subject_id = i.subject_id
     AND a.hadm_id    = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
)
SELECT DISTINCT
  discharge_group,
  COUNT(*)   OVER(PARTITION BY discharge_group)                 AS n_patients,
  AVG(los)   OVER(PARTITION BY discharge_group)                 AS mean_los_days,
  PERCENTILE_CONT(los, 0.50) OVER(PARTITION BY discharge_group) AS p50_los_days,
  PERCENTILE_CONT(los, 0.75) OVER(PARTITION BY discharge_group) AS p75_los_days,
  PERCENTILE_CONT(los, 0.90) OVER(PARTITION BY discharge_group) AS p90_los_days
FROM
  base
ORDER BY
  discharge_group;