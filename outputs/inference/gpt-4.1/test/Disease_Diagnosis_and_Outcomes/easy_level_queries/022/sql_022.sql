WITH ischemic_stroke_codes AS (
  -- List of ICD codes for ischemic stroke (ICD-9 and ICD-10)
  SELECT '433' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '434' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '436' AS icd_code, 9 AS icd_version UNION ALL
  SELECT 'I63' AS icd_code, 10 AS icd_version UNION ALL
  SELECT 'I65' AS icd_code, 10 AS icd_version UNION ALL
  SELECT 'I66' AS icd_code, 10 AS icd_version
),
primary_stroke_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age,
    pat.gender,
    diag.icd_code,
    diag.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN ischemic_stroke_codes codes
      ON diag.icd_version = codes.icd_version
         AND (
           -- For ICD-9, match 3-digit code prefix (e.g., 433.x1, 434.x1, 436)
           (diag.icd_version = 9 AND LEFT(diag.icd_code, 3) = codes.icd_code)
           -- For ICD-10, match 3-character code prefix (e.g., I63.x)
           OR (diag.icd_version = 10 AND LEFT(diag.icd_code, 3) = codes.icd_code)
         )
  WHERE
    diag.seq_num = 1 -- primary diagnosis
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 71 AND 81
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  quantiles[OFFSET(1)] AS los_25th_percentile_days,
  quantiles[OFFSET(3)] AS los_75th_percentile_days
FROM (
  SELECT
    APPROX_QUANTILES(
      TIMESTAMP_DIFF(dischtime, admittime, DAY),
      4
    ) AS quantiles
  FROM primary_stroke_admissions
);