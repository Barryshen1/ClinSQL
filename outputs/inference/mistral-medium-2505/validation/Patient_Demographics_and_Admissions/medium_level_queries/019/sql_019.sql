WITH filtered_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admission_type = 'TRANSFER'
    AND a.dischtime IS NOT NULL
)

SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN discharge_location LIKE '%HOSPICE%' THEN 'Discharged to hospice'
    WHEN discharge_location = 'HOME' THEN 'Discharged home'
    ELSE 'Other discharge location'
  END AS discharge_disposition,
  COUNT(*) AS patient_count,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days
FROM
  filtered_patients
GROUP BY
  discharge_disposition
ORDER BY
  patient_count DESC;