WITH sepsis_codes AS (
  -- List of ICD codes for sepsis/septic shock (ICD-9 and ICD-10)
  SELECT '99591' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '99592', 9 UNION ALL
  SELECT '038', 9 UNION ALL
  SELECT '78552', 9 UNION ALL
  SELECT 'A40', 10 UNION ALL
  SELECT 'A41', 10 UNION ALL
  SELECT 'R652', 10
),
primary_sepsis_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.gender,
    pat.anchor_age
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS adm
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN
    sepsis_codes AS sc
    ON diag.icd_version = sc.icd_version
    -- Match codes that start with the sepsis code (for wildcards)
    AND (
      diag.icd_code = sc.icd_code
      OR diag.icd_code LIKE CONCAT(sc.icd_code, '%')
    )
  WHERE
    diag.seq_num = 1 -- primary diagnosis
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
)
SELECT
  PERCENTILE_CONT(los, 0.25) OVER() AS los_25th_percentile,
  PERCENTILE_CONT(los, 0.75) OVER() AS los_75th_percentile
FROM (
  SELECT
    subject_id,
    hadm_id,
    -- LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS FLOAT64) AS los
  FROM
    primary_sepsis_admissions
  WHERE
    dischtime > admittime
)
WHERE
  los IS NOT NULL
  AND los > 0;