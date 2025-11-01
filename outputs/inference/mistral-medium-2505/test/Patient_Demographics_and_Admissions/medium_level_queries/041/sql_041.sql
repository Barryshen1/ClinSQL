WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24 AS los_days,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/Rehab/LTACH'
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND a.admission_type = 'ELECTIVE'
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
)

SELECT
  discharge_outcome,
  COUNT(*) AS patient_count,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(PERCENTILE_CONT(los_days, 0.5) OVER(), 2) AS median_los,
  ROUND(PERCENTILE_CONT(los_days, 0.75) OVER(), 2) AS p75_los,
  ROUND(PERCENTILE_CONT(los_days, 0.9) OVER(), 2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_le_7_days
FROM
  patient_admissions
GROUP BY
  discharge_outcome, los_days
ORDER BY
  discharge_outcome;