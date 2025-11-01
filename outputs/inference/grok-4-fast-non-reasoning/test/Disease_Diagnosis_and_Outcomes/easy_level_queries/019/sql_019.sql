WITH eligible_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hospital_expire_flag = 0
),
sepsis_patients AS (
  SELECT DISTINCT 
    ea.subject_id,
    ea.hadm_id
  FROM 
    eligible_admissions ea
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ea.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    d.seq_num = 1  -- Primary diagnosis
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65%')
)
SELECT 
  STDDEV(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS sd_los_days
FROM 
  sepsis_patients sp
INNER JOIN 
  eligible_admissions ea
  ON sp.subject_id = ea.subject_id 
  AND ea.rn = 1  -- Earliest admission per patient for LOS calculation
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON ea.hadm_id = a.hadm_id;