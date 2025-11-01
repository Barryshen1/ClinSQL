WITH hf_admissions AS (
  -- Step 1 & 2: filter for male patients age 68-78 with heart failure admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      -- heart failure diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
admission_flags AS (
  -- Step 3: for each HF admission, determine CKD and Diabetes
  SELECT
    ha.*,
    CASE WHEN ha.los < 8 THEN '<8' ELSE '>=8' END AS los_group,
    -- CKD flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = ha.hadm_id
        AND LOWER(dd.long_title) LIKE '%chronic kidney%'
    ) THEN 1 ELSE 0 END AS ckd_flag,
    -- Diabetes flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = ha.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabet%'
    ) THEN 1 ELSE 0 END AS dm_flag
  FROM hf_admissions ha
)
-- Step 4: aggregate
SELECT
  los_group,
  COUNT(*) AS admissions_n,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 1)      AS ckd_prevalence_pct,
  ROUND(100.0 * SUM(dm_flag) / COUNT(*), 1)       AS diabetes_prevalence_pct
FROM admission_flags
GROUP BY los_group
ORDER BY los_group;