WITH primary_acs AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    'Primary' AS diagnosis_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.anchor_age BETWEEN 77 AND 87
    AND p.gender = 'F'
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '410%') OR
      (d.icd_version = 'ICD-10' AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%'))
    )
),
secondary_acs AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    'Secondary' AS diagnosis_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.anchor_age BETWEEN 77 AND 87
    AND p.gender = 'F'
    AND a.hospital_expire_flag = 0
    AND d.seq_num > 1
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '410%') OR
      (d.icd_version = 'ICD-10' AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%'))
    )
),
acs_admissions AS (
  SELECT * FROM primary_acs
  UNION ALL
  SELECT * FROM secondary_acs
),
los_grouped AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    gender,
    anchor_age,
    diagnosis_type,
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM acs_admissions
  WHERE DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 BETWEEN 1 AND 8
),
imaging_counts AS (
  SELECT 
    a.hadm_id,
    a.los_group,
    a.diagnosis_type,
    COUNT(h.hcpcs_cd) AS rad_count
  FROM 
    los_grouped a
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON a.hadm_id = h.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE 
    (dh.category LIKE '%Radiology%' OR h.hcpcs_cd LIKE '7%')
  GROUP BY 
    a.hadm_id, a.los_group, a.diagnosis_type
),
admission_totals AS (
  SELECT 
    hadm_id,
    los_group,
    diagnosis_type,
    COALESCE(rad_count, 0) AS rad_count
  FROM los_grouped lg
  LEFT JOIN imaging_counts ic 
    ON lg.hadm_id = ic.hadm_id 
    AND lg.los_group = ic.los_group
    AND lg.diagnosis_type = ic.diagnosis_type
)
SELECT 
  diagnosis_type,
  los_group,
  AVG(rad_count) AS mean_rad_count,
  MIN(rad_count) AS min_rad_count,
  MAX(rad_count) AS max_rad_count,
  COUNT(*) AS num_admissions
FROM admission_totals
WHERE los_group IS NOT NULL
GROUP BY diagnosis_type, los_group
ORDER BY diagnosis_type, 
  CASE los_group WHEN '1-4 days' THEN 1 ELSE 2 END;