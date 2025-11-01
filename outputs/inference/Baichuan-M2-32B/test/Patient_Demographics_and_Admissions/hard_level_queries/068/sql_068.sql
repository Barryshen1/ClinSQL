WITH admissions_with_diagnosis AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.insurance,
    a.admission_location,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    d_icd.long_title,
    -- Compute age at admission using anchor_year and anchor_age to approximate birth year
    TIMESTAMP_DIFF(
      CAST(a.admittime AS TIMESTAMP),
      CAST(DATE(p.anchor_year - p.anchor_age, 1, 1) AS TIMESTAMP),
      YEAR
    ) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE d.seq_num = 1  -- principal diagnosis
    AND TRIM(p.gender) = 'M'  -- gender from patients table
    AND TRIM(a.insurance) = 'Medicare'
    AND TRIM(a.admission_location) = 'SNF'
    AND d_icd.long_title LIKE '%dehydration%'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND a.admittime IS NOT NULL
)
SELECT COUNT(DISTINCT hadm_id) AS num_admissions
FROM admissions_with_diagnosis
WHERE age_at_admission BETWEEN 43 AND 53;