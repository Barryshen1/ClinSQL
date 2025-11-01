WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Calculate LOS in days with fractional precision
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in_hospital_death'
      WHEN a.hospital_expire_flag = 0
           AND a.discharge_location = 'HOME' THEN 'discharged_home'
      WHEN a.hospital_expire_flag = 0
           AND LOWER(a.discharge_location) LIKE '%hospice%' THEN 'discharged_hospice'
      ELSE NULL
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND LOWER(a.admission_location) LIKE '%transfer%'
    AND a.dischtime IS NOT NULL
),
stratified AS (
  SELECT
    discharge_group,
    los_days
  FROM
    filtered_admissions
  WHERE
    discharge_group IS NOT NULL
)
SELECT
  discharge_group,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS stddev_los_days,
  COUNT(*) AS n_patients
FROM
  stratified
GROUP BY
  discharge_group
ORDER BY
  discharge_group;