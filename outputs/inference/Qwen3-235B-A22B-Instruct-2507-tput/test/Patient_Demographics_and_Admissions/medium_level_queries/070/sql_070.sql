WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24.0 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_location IN ('EMERGENCY ROOM', 'ER')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime  -- Valid LOS
),
categorized_los AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Discharged Home'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
      ELSE NULL
    END AS outcome_group
  FROM
    patient_admissions
  WHERE
    discharge_location = 'HOME'
    OR discharge_location LIKE 'HOSPICE%'
    OR hospital_expire_flag = 1
)
SELECT
  outcome_group,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los_days,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los_days,
  SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*) AS pct_rank_10_days
FROM
  categorized_los
GROUP BY
  outcome_group
ORDER BY
  outcome_group;