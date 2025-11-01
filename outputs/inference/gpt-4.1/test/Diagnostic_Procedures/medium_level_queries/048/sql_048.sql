WITH heart_failure_icds AS (
  -- Get all ICD codes for heart failure (ICD-9: 428.*, ICD-10: I50.*)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
hf_admissions AS (
  -- Admissions for men aged 90-100 with HF diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
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
  JOIN heart_failure_icds hf
    ON diag.icd_code = hf.icd_code AND diag.icd_version = hf.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
),
admission_hf_type AS (
  -- For each admission, determine if HF is primary (seq_num=1) or secondary (seq_num>1)
  SELECT
    subject_id,
    hadm_id,
    MIN(seq_num) AS min_seq_num
  FROM hf_admissions
  GROUP BY subject_id, hadm_id
),
admission_los AS (
  -- Calculate LOS and bin
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
mri_ct_icds AS (
  -- Get all ICD procedure codes for MRI or CT
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%mri%'
     OR LOWER(long_title) LIKE '%ct%'
),
admission_mri_ct_count AS (
  -- Count MRI/CT procedures per admission
  SELECT
    proc.hadm_id,
    COUNT(*) AS mri_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN mri_ct_icds mri_ct
    ON proc.icd_code = mri_ct.icd_code AND proc.icd_version = mri_ct.icd_version
  GROUP BY proc.hadm_id
),
final AS (
  -- Combine all info per admission
  SELECT
    t.subject_id,
    t.hadm_id,
    l.los_days,
    CASE
      WHEN l.los_days BETWEEN 1 AND 3 THEN 'LOS 1-3'
      WHEN l.los_days BETWEEN 4 AND 7 THEN 'LOS 4-7'
      ELSE NULL
    END AS los_bin,
    CASE
      WHEN t.min_seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS hf_type,
    IFNULL(m.mri_ct_count, 0) AS mri_ct_count
  FROM admission_hf_type t
  JOIN admission_los l
    ON t.hadm_id = l.hadm_id
  LEFT JOIN admission_mri_ct_count m
    ON t.hadm_id = m.hadm_id
)
SELECT
  los_bin,
  hf_type,
  COUNT(*) AS admission_count,
  ROUND(AVG(mri_ct_count),2) AS mean_mri_ct_per_admission
FROM final
WHERE los_bin IS NOT NULL
GROUP BY los_bin, hf_type
ORDER BY los_bin, hf_type;