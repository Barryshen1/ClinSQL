WITH ultrasound_procs AS (
  SELECT 
    p.hadm_id, 
    COUNT(*) AS num_ultrasounds
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%ultrasound%' 
    OR LOWER(d.long_title) LIKE '%echocardiography%'
  GROUP BY 
    p.hadm_id
),
admissions_filtered AS (
  SELECT 
    a.hadm_id, 
    a.admission_type,
    p.gender, 
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY')
)
SELECT 
  CASE 
    WHEN af.admission_type = 'EMERGENCY' THEN 'ED'
    ELSE 'Elective'
  END AS admission_type_group,
  CASE 
    WHEN af.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN af.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  AVG(COALESCE(up.num_ultrasounds, 0)) AS mean_ultrasounds,
  MIN(COALESCE(up.num_ultrasounds, 0)) AS min_ultrasounds,
  MAX(COALESCE(up.num_ultrasounds, 0)) AS max_ultrasounds,
  COUNT(*) AS num_admissions  -- For context: number of admissions in each stratum
FROM 
  admissions_filtered af
LEFT JOIN 
  ultrasound_procs up ON af.hadm_id = up.hadm_id
WHERE 
  af.los_days BETWEEN 1 AND 7
GROUP BY 
  admission_type_group, los_group
ORDER BY 
  admission_type_group, los_group;