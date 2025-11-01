WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    )
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    WHEN discharge_location = 'HOME' THEN 'Discharged Home'
    WHEN discharge_location LIKE 'HOSPICE%' THEN 'Discharged to Hospice'
  END AS discharge_group,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24 * 60 * 60)) AS mean_los_days,
  STDDEV(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24 * 60 * 60)) AS sd_los_days
FROM filtered_admissions
WHERE 
  hospital_expire_flag = 1
  OR discharge_location = 'HOME'
  OR discharge_location LIKE 'HOSPICE%'
GROUP BY discharge_group
ORDER BY discharge_group;