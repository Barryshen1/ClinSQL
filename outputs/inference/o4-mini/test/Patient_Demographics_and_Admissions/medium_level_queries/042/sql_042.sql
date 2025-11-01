WITH admission_los AS (
  SELECT
    adm.hospital_expire_flag AS in_hospital_death_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON p.subject_id = adm.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND adm.admission_type != 'ELECTIVE'
    AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) > 0
)
SELECT
  in_hospital_death_flag,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(
    (APPROX_QUANTILES(los_days, 100))[OFFSET(50)],
    2
  ) AS median_los_days,
  ROUND(
    (APPROX_QUANTILES(los_days, 100))[OFFSET(75)],
    2
  ) AS p75_los_days,
  ROUND(
    (APPROX_QUANTILES(los_days, 100))[OFFSET(90)],
    2
  ) AS p90_los_days,
  ROUND(
    SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*),
    4
  ) AS pct_rank_5_day
FROM
  admission_los
GROUP BY
  in_hospital_death_flag
ORDER BY
  in_hospital_death_flag;