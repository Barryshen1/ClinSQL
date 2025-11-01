WITH base AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN adm.discharge_location = 'HOME' THEN 'Home'
      WHEN adm.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/rehab/LTACH'
      ELSE 'Other' 
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND adm.dischtime IS NOT NULL
),
discharge_groups AS (
  SELECT 
    discharge_group,
    los_days,
    CASE WHEN los_days >= 7 THEN 1 ELSE 0 END AS los_ge_7,
    PERCENTILE_CONT(los_days, 0.14) OVER (PARTITION BY discharge_group) AS percentile_14
  FROM base
  WHERE discharge_group IN ('Home', 'SNF/rehab/LTACH', 'In-hospital death')
)
SELECT 
  discharge_group,
  COUNT(*) AS total_admissions,
  SUM(los_ge_7) AS admissions_los_ge_7,
  ROUND(SUM(los_ge_7) / COUNT(*), 3) AS proportion_los_ge_7,
  MAX(percentile_14) AS percentile_14  -- All values are the same per group
FROM discharge_groups
GROUP BY discharge_group
ORDER BY discharge_group;