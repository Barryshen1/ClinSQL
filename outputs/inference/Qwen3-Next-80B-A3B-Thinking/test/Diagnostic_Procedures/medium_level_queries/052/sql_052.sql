WITH ultrasound_procedures AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE d.long_description LIKE '%ultrasound%' OR d.long_description LIKE '%echocardiogram%'
  
  UNION ALL
  
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON p.itemid = d.itemid
  WHERE d.label LIKE '%ultrasound%' OR d.label LIKE '%echocardiogram%'
),
ultrasound_counts AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM ultrasound_procedures
  GROUP BY hadm_id
),
admissions_data AS (
  SELECT 
    a.hadm_id,
    a.admission_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN ultrasound_counts uc ON a.hadm_id = uc.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
)
SELECT 
  CASE 
    WHEN admission_type = 'EMERGENCY' THEN 'ED'
    WHEN admission_type = 'ELECTIVE' THEN 'elective'
    ELSE NULL 
  END AS admission_category,
  CASE 
    WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE NULL 
  END AS los_group,
  AVG(ultrasound_count) AS mean_ultrasound,
  MIN(ultrasound_count) AS min_ultrasound,
  MAX(ultrasound_count) AS max_ultrasound
FROM admissions_data
GROUP BY admission_category, los_group
HAVING admission_category IS NOT NULL
  AND los_group IS NOT NULL;