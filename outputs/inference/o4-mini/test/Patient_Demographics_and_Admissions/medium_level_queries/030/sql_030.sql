WITH filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Compute LOS in days (decimal)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type = 'ELECTIVE'
),
with_percentiles AS (
  SELECT
    hospital_expire_flag,
    los,
    -- Compute percentiles over each mortality group
    PERCENTILE_CONT(los, 0.25) OVER (PARTITION BY hospital_expire_flag) AS p25,
    PERCENTILE_CONT(los, 0.50) OVER (PARTITION BY hospital_expire_flag) AS p50,
    PERCENTILE_CONT(los, 0.75) OVER (PARTITION BY hospital_expire_flag) AS p75,
    PERCENTILE_CONT(los, 0.90) OVER (PARTITION BY hospital_expire_flag) AS p90
  FROM filtered
)
SELECT
  hospital_expire_flag,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(ANY_VALUE(p25), 2) AS los_p25_days,
  ROUND(ANY_VALUE(p50), 2) AS los_p50_days,
  ROUND(ANY_VALUE(p75), 2) AS los_p75_days,
  ROUND(ANY_VALUE(p90), 2) AS los_p90_days
FROM
  with_percentiles
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;