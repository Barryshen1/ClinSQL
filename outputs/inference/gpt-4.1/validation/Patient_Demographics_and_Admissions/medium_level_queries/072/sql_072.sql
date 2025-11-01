WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    p.gender,
    s.curr_service,
    -- Calculate LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.services` s
      ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND s.curr_service = 'MED'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, cohort_grouped AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS discharge_group
  FROM cohort
)
SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 2) AS median_los,
  ROUND(SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END) / COUNT(*), 3) AS proportion_los_le_5
FROM
  cohort_grouped
WHERE
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group;