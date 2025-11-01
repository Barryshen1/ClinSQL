WITH acs_icd_codes AS (
  -- List ACS ICD codes (ICD-9 and ICD-10)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-9 ACS codes
    (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^410') OR
      REGEXP_CONTAINS(icd_code, r'^411') OR
      icd_code = '412' OR
      REGEXP_CONTAINS(icd_code, r'^413') OR
      REGEXP_CONTAINS(icd_code, r'^414')
    ))
    -- ICD-10 ACS codes
    OR (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I2[0-5]')
    ))
),
acs_admissions AS (
  -- Find admissions with ACS diagnosis, age 77–87, female
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    diag.seq_num,
    diag.icd_code,
    diag.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN acs_icd_codes acs
    ON diag.icd_code = acs.icd_code AND diag.icd_version = acs.icd_version
  WHERE
    pat.anchor_age BETWEEN 77 AND 87
    AND pat.gender = 'F'
),
acs_adm_type AS (
  -- For each admission, determine if ACS is primary or secondary
  SELECT
    subject_id,
    hadm_id,
    MIN(seq_num) AS min_seq_num
  FROM acs_admissions
  GROUP BY subject_id, hadm_id
),
acs_final AS (
  -- Add LOS and diagnosis type
  SELECT
    a.subject_id,
    a.hadm_id,
    a.anchor_age,
    a.gender,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN t.min_seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM acs_admissions a
  JOIN acs_adm_type t
    ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  GROUP BY a.subject_id, a.hadm_id, a.anchor_age, a.gender, a.admittime, a.dischtime, t.min_seq_num
),
ct_rad_icd_codes AS (
  -- Find procedure ICD codes for radiography/CT
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    LOWER(long_title) LIKE '%radiograph%'
    OR LOWER(long_title) LIKE '%x-ray%'
    OR LOWER(long_title) LIKE '%ct%'
    OR LOWER(long_title) LIKE '%computed tomography%'
    OR LOWER(long_title) LIKE '%chest x-ray%'
    OR LOWER(long_title) LIKE '%chest radiograph%'
    OR LOWER(long_title) LIKE '%chest ct%'
),
ct_rad_counts AS (
  -- Count radiography/CT procedures per admission
  SELECT
    proc.subject_id,
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS ct_rad_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN ct_rad_icd_codes ct
    ON proc.icd_code = ct.icd_code AND proc.icd_version = ct.icd_version
  GROUP BY proc.subject_id, proc.hadm_id
),
acs_with_ct_rad AS (
  -- Join ACS admissions with CT/radiography counts (default to 0 if none)
  SELECT
    acs.subject_id,
    acs.hadm_id,
    acs.anchor_age,
    acs.gender,
    acs.los_days,
    acs.diagnosis_type,
    IFNULL(ct.ct_rad_count, 0) AS ct_rad_count
  FROM acs_final acs
  LEFT JOIN ct_rad_counts ct
    ON acs.subject_id = ct.subject_id AND acs.hadm_id = ct.hadm_id
),
acs_los_grouped AS (
  -- Assign LOS group
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group
  FROM acs_with_ct_rad
  WHERE los_days BETWEEN 1 AND 8
)
SELECT
  los_group,
  diagnosis_type,
  AVG(ct_rad_count) AS mean_ct_rad_count,
  MIN(ct_rad_count) AS min_ct_rad_count,
  MAX(ct_rad_count) AS max_ct_rad_count,
  COUNT(*) AS n_admissions
FROM acs_los_grouped
WHERE los_group IS NOT NULL
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;