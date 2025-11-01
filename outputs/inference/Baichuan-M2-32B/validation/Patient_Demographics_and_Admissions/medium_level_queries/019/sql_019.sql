WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 63 AND 73
    AND a.admission_type = 'transfer from another hospital'
    AND a.dischtime IS NOT NULL
    AND (
      a.hospital_expire_flag = 1
      OR a.discharge_location IN ('Home', 'Hospice care')
    )
),
los_data AS (
  SELECT
    subject_id,
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,  -- Fixed function and added unit
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'Home' THEN 'discharged home'
      WHEN discharge_location = 'Hospice care' THEN 'discharged to hospice'
    END AS discharge_group
  FROM filtered_admissions
)
SELECT
  discharge_group,
  COUNT(*) AS num_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days
FROM los_data
GROUP BY discharge_group
ORDER BY discharge_group;