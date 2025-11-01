WITH aki_icd_codes AS (
  -- List of AKI ICD codes (ICD-9 and ICD-10)
  SELECT '584' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '5840', 9 UNION ALL
  SELECT '5845', 9 UNION ALL
  SELECT '5846', 9 UNION ALL
  SELECT '5847', 9 UNION ALL
  SELECT '5848', 9 UNION ALL
  SELECT '5849', 9 UNION ALL
  SELECT 'N17', 10 UNION ALL
  SELECT 'N170', 10 UNION ALL
  SELECT 'N171', 10 UNION ALL
  SELECT 'N172', 10 UNION ALL
  SELECT 'N178', 10 UNION ALL
  SELECT 'N179', 10
),
first_admissions AS (
  -- Get first admission for each patient
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN (
    SELECT
      subject_id,
      MIN(admittime) AS first_admittime
    FROM
      physionet-data.mimiciv_3_1_hosp.admissions
    GROUP BY subject_id
  ) fa
    ON a.subject_id = fa.subject_id
    AND a.admittime = fa.first_admittime
),
aki_patients AS (
  -- Patients with AKI in their first admission
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime
  FROM
    first_admissions fa
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON fa.hadm_id = d.hadm_id
  INNER JOIN aki_icd_codes ak
    ON d.icd_code = ak.icd_code AND d.icd_version = ak.icd_version
),
target_patients AS (
  -- Filter for females aged 70-80
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.admittime,
    ap.dischtime
  FROM
    aki_patients ap
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON ap.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND ap.dischtime IS NOT NULL
)
SELECT
  STDDEV_SAMP(
    TIMESTAMP_DIFF(dischtime, admittime, DAY)
  ) AS sd_los_days
FROM
  target_patients
;