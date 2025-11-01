WITH base AS (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital mortality'
      ELSE 'Discharged alive'
    END AS outcome_group,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type = 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  outcome_group,
  n,
  mean_los,
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(50)] AS p50,
  quantiles[OFFSET(75)] AS p75,
  quantiles[OFFSET(90)] AS p90
FROM (
  SELECT
    outcome_group,
    COUNT(*) AS n,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100) AS quantiles
  FROM base
  GROUP BY outcome_group
) AS t
ORDER BY outcome_group;