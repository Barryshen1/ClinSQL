WITH pneumonia_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%pneumonia%'
    AND icd_version = 10
),
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at admission
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
ranked_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM first_admissions
  WHERE age_at_admission BETWEEN 83 AND 93
),
cohort_first_admission AS (
  SELECT ra.subject_id, ra.hadm_id, ra.hospital_expire_flag
  FROM ranked_admissions ra
  WHERE rn = 1
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN pneumonia_codes pc ON di.icd_code = pc.icd_code AND di.icd_version = 10
    WHERE di.hadm_id = ra.hadm_id
  )
)
SELECT
  100.0 * SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_rate_pct
FROM cohort_first_admission;