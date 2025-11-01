WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.insurance,
    a.admission_location,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    d.icd_code,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE 
    -- Female
    UPPER(p.gender) = 'F'   -- Fixed: gender is in patients table (p), not admissions (a)
    -- Medicare insurance
    AND UPPER(a.insurance) = 'MEDICARE'
    -- Admitted from ED
    AND UPPER(a.admission_location) IN ('ED', 'EMERGENCY DEPARTMENT', 'EMERGENCY DEPT', 'EMERGENCY', 'ER')
    -- Documented discharge
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0
    -- Age 68-78 at admission
    AND TIMESTAMP_DIFF(
          a.admittime, 
          DATE(p.anchor_year - p.anchor_age, 1, 1), 
          YEAR
        ) BETWEEN 68 AND 78
    -- Principal hemorrhagic stroke (ICD-9/10)
    AND (
        (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
        OR
        (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
)
SELECT COUNT(DISTINCT hadm_id) AS count
FROM eligible_admissions;