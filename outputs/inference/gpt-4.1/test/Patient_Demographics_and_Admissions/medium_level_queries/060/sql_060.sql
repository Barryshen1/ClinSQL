WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_location LIKE '%ED%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, cohort_los AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM cohort
)
SELECT
  discharge_outcome,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days,
  ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_le_10_days
FROM
  cohort_los
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;