WITH pancreatitis_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    d.seq_num,
    CASE 
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN 1
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN 2
      ELSE NULL
    END AS los_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.hospital_expire_flag = 0
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'K85.%'
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_counts AS (
  SELECT 
    pa.hadm_id,
    pa.diagnosis_type,
    pa.los_group,
    COUNT(DISTINCT pr.icd_code) AS imaging_count
  FROM 
    pancreatitis_admissions pa
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pa.hadm_id = pr.hadm_id
    AND pr.icd_version = '10'
    AND (pr.icd_code LIKE 'BW2%'  -- CT scans
         OR pr.icd_code LIKE 'BA%'  -- Radiography/X-rays
         OR pr.icd_code LIKE 'BQ0%')  -- Other imaging (e.g., ultrasound if relevant)
  WHERE 
    pa.los_group IS NOT NULL
  GROUP BY 
    pa.hadm_id, pa.diagnosis_type, pa.los_group
)
SELECT 
  ic.los_group,
  CASE 
    WHEN ic.los_group = 1 THEN '1-3 days'
    WHEN ic.los_group = 2 THEN '4-7 days'
  END AS los_description,
  ic.diagnosis_type,
  COUNT(DISTINCT ic.hadm_id) AS admission_count,
  ROUND(AVG(ic.imaging_count), 2) AS mean_imaging_per_admission
FROM 
  imaging_counts ic
GROUP BY 
  ic.los_group, 
  ic.diagnosis_type
ORDER BY 
  ic.los_group, 
  ic.diagnosis_type;