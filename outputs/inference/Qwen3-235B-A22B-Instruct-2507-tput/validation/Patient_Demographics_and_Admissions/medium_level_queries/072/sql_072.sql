WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
medicine_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.services s
    WHERE s.hadm_id = pa.hadm_id
      AND s.curr_service = 'MED'
  )
),
stratified AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Discharged to hospice'
      WHEN discharge_location = 'HOME' THEN 'Discharged home'
      ELSE NULL
    END AS discharge_group
  FROM medicine_admissions
  WHERE discharge_location IN ('HOME', 'HOSPICE-HOME', 'HOSPICE-NURSING FACILITY')
    OR hospital_expire_flag = 1
    OR discharge_location = 'HOME'
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  AVG(CASE WHEN los_days <= 5 THEN 1.0 ELSE 0.0 END) AS proportion_los_le_5_days
FROM stratified
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;