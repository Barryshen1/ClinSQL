WITH acs_icd_codes AS (
  -- List ACS ICD codes (ICD-9 and ICD-10)
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '411', 9 UNION ALL
  SELECT '413', 9 UNION ALL
  SELECT 'I20', 10 UNION ALL
  SELECT 'I21', 10 UNION ALL
  SELECT 'I22', 10 UNION ALL
  SELECT 'I23', 10
),
diagnostic_proc_codes AS (
  -- ICD-9 diagnostic procedures: codes starting with 87–99
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(87|88|89|90|91|92|93|94|95|96|97|98|99)'))
),
acs_admissions AS (
  -- Admissions for males 59–69 with ACS diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    diag.icd_code,
    diag.icd_version,
    diag.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN acs_icd_codes acs
    ON diag.icd_code = acs.icd_code AND diag.icd_version = acs.icd_version
  WHERE pat.anchor_age BETWEEN 59 AND 69
    AND pat.gender = 'M'
),
acs_admission_type AS (
  -- For each ACS admission, determine if ACS was primary or secondary
  SELECT
    subject_id,
    hadm_id,
    MIN(seq_num) AS min_seq_num
  FROM acs_admissions
  GROUP BY subject_id, hadm_id
),
admission_los AS (
  -- Calculate LOS and group
  SELECT
    a.subject_id,
    a.hadm_id,
    a.min_seq_num,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group,
    CASE
      WHEN a.min_seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM acs_admission_type a
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON a.hadm_id = adm.hadm_id
  WHERE TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
diagnostic_proc_counts AS (
  -- Count diagnostic procedures per admission
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.los_group,
    adm.diagnosis_type,
    COUNT(proc.icd_code) AS num_diag_procs
  FROM admission_los adm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.hadm_id = proc.hadm_id
    AND proc.icd_version = 9
  LEFT JOIN diagnostic_proc_codes dpc
    ON proc.icd_code = dpc.icd_code AND proc.icd_version = dpc.icd_version
  WHERE adm.los_group IS NOT NULL
  GROUP BY adm.subject_id, adm.hadm_id, adm.los_group, adm.diagnosis_type
),
final_stats AS (
  -- Aggregate percentiles per group
  SELECT
    los_group,
    diagnosis_type,
    APPROX_QUANTILES(num_diag_procs, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(num_diag_procs, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(num_diag_procs, 4)[OFFSET(3)] AS p75
  FROM diagnostic_proc_counts
  WHERE los_group IS NOT NULL
  GROUP BY los_group, diagnosis_type
)
SELECT
  los_group,
  diagnosis_type,
  p25,
  p50,
  p75
FROM final_stats
ORDER BY los_group, diagnosis_type;