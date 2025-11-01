WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
discharge_groups AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'Home' THEN 'Home'
      WHEN discharge_location IN ('Skilled Nursing Facility', 'Rehabilitation Facility', 'Long Term Acute Care Hospital') THEN 'SNF/rehab/LTACH'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)
SELECT 
  discharge_group,
  COUNT(*) AS total_admissions,
  COUNTIF(los >= 7) AS count_ge7,
  COUNTIF(los >= 7) / COUNT(*) AS proportion_ge7,
  APPROX_QUANTILES(los, 100)[OFFSET(14)] AS p14_los
FROM discharge_groups
WHERE discharge_group IN ('In-hospital death', 'Home', 'SNF/rehab/LTACH')
GROUP BY discharge_group
ORDER BY discharge_group;