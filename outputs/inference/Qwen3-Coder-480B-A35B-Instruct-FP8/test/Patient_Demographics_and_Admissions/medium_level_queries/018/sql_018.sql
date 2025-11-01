WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location NOT IN ('EMERGENCY ROOM', 'WALK-IN/SELF REFERRAL')
),
discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'INSTITUTION', 'OTHER FACILITY') THEN 'Facility'
      ELSE 'Other'
    END AS disch_group
  FROM
    cohort
)
SELECT
  disch_group,
  COUNT(*) AS n,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3_los,
  ROUND(AVG(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100, 2) AS pct_los_le_10
FROM
  discharge_groups
WHERE
  disch_group IN ('Home', 'Facility', 'Death')
GROUP BY
  disch_group
ORDER BY
  disch_group;