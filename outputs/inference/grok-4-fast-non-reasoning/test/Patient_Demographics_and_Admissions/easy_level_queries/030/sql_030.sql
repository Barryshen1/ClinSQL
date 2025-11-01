WITH first_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS row_num
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.hospital_expire_flag = 0
),
anticoagulant_admissions AS (
  SELECT DISTINCT 
    fa.subject_id,
    fa.hadm_id,
    fa.los_days
  FROM 
    first_admissions fa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    fa.subject_id = pr.subject_id 
    AND fa.hadm_id = pr.hadm_id
  WHERE 
    fa.row_num = 1
    AND fa.los_days > 0
    AND LOWER(pr.drug) LIKE '%warfarin%'
       OR LOWER(pr.drug) LIKE '%heparin%'
       OR LOWER(pr.drug) LIKE '%enoxaparin%'
       OR LOWER(pr.drug) LIKE '%rivaroxaban%'
       OR LOWER(pr.drug) LIKE '%apixaban%'
       OR LOWER(pr.drug) LIKE '%dabigatran%'
)
SELECT 
  STDDEV(los_days) AS sd_first_los_days
FROM 
  anticoagulant_admissions;