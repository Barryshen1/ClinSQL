WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
      WHEN a.discharge_location = 'HOME' THEN 'HOME'
      ELSE 'FACILITY'
    END AS outcome_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type IN ('URGENT', 'EMERGENCY')
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year))
        BETWEEN 37 AND 47
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0  -- Exclude invalid LOS
)

SELECT
  outcome_group,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  (COUNTIF(los_days < 7) + 0.5 * COUNTIF(los_days = 7)) / COUNT(*) AS percentile_rank_7day
FROM cohort
GROUP BY outcome_group
ORDER BY outcome_group;