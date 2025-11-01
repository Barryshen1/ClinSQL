WITH dka_hhs_icd AS (
  -- List of ICD codes for DKA/HHS (ICD-9 and ICD-10)
  SELECT '25010' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '25011', 9 UNION ALL
  SELECT '25012', 9 UNION ALL
  SELECT '25013', 9 UNION ALL
  SELECT '25020', 9 UNION ALL
  SELECT '25021', 9 UNION ALL
  SELECT '25022', 9 UNION ALL
  SELECT '25023', 9 UNION ALL
  SELECT 'E101', 10 UNION ALL
  SELECT 'E111', 10 UNION ALL
  SELECT 'E131', 10 UNION ALL
  SELECT 'E141', 10 UNION ALL
  SELECT 'E100', 10 UNION ALL
  SELECT 'E110', 10 UNION ALL
  SELECT 'E130', 10 UNION ALL
  SELECT 'E140', 10
),
primary_dka_hhs_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.gender,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    INNER JOIN dka_hhs_icd icd
      ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE
    diag.seq_num = 1 -- primary diagnosis
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  percentile_cont(
    TIMESTAMP_DIFF(dischtime, admittime, MINUTE)/1440.0, 0.25
  ) OVER () AS los_25th_percentile_days
FROM
  primary_dka_hhs_admissions
WHERE
  TIMESTAMP_DIFF(dischtime, admittime, MINUTE) > 0;