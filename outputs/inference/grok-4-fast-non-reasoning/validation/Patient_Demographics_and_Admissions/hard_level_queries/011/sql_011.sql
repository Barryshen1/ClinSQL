WITH cohort AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    -- Patient demographics and survival
    CAST(p.gender AS STRING) = 'F'
    AND (p.dod IS NULL OR p.dod > a.admittime)
    -- Age range
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 68 AND 78
    -- Insurance
    AND LOWER(TRIM(a.insurance)) = 'medicare'
    -- ED admission
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
    -- Principal hemorrhagic stroke (ICD-9/10)
    AND d.seq_num = 1
    AND (
      (d.icd_version = '9' AND d.icd_code LIKE '43%')  -- ICD-9: 430-432
      OR 
      (d.icd_version = '10' AND d.icd_code LIKE 'I6%') -- ICD-10: I60-I62
    )
    -- Documented discharge (alive)
    AND CAST(a.hospital_expire_flag AS INT64) = 0
    AND a.dischtime IS NOT NULL
)

SELECT 
  COUNT(hadm_id) AS num_index_admissions
FROM cohort;