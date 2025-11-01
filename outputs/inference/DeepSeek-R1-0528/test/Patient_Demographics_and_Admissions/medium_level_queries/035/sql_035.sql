WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
)

SELECT
  discharge_outcome,
  COUNT(*) AS n_stays,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q1_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q3_los_days,
  ROUND(SAFE_DIVIDE(COUNTIF(los_days <= 14), COUNT(*)) * 100, 1) AS percentile_rank_14_day
FROM
  cohort
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;