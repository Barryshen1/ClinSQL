WITH aki_codes AS (
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
aki_admissions AS (
  -- Find admissions with AKI, stratify by primary/secondary
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    CASE
      WHEN MIN(CASE WHEN diag.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS aki_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
    JOIN physionet-data.mimiciv_3_1_hosp.patients pat ON adm.subject_id = pat.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
      ON adm.hadm_id = diag.hadm_id
    JOIN aki_codes ac
      ON diag.icd_code = ac.icd_code AND diag.icd_version = ac.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
  GROUP BY
    adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender, adm.admittime, adm.dischtime
),
aki_los_grouped AS (
  -- Filter for LOS groups
  SELECT
    *,
    CASE
      WHEN los BETWEEN 1 AND 4 THEN '1-4'
      WHEN los BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group
  FROM aki_admissions
  WHERE los BETWEEN 1 AND 7
),
mri_ct_orders AS (
  -- Find MRI/CT orders per admission
  SELECT
    poe.subject_id,
    poe.hadm_id,
    COUNT(DISTINCT poe.poe_id) AS mri_ct_count
  FROM
    physionet-data.mimiciv_3_1_hosp.poe poe
    JOIN physionet-data.mimiciv_3_1_hosp.poe_detail pd
      ON poe.poe_id = pd.poe_id AND poe.poe_seq = pd.poe_seq
  WHERE
    LOWER(pd.field_value) LIKE '%mri%'
    OR LOWER(pd.field_value) LIKE '%ct%'
  GROUP BY
    poe.subject_id, poe.hadm_id
),
final AS (
  -- Join AKI admissions with MRI/CT counts
  SELECT
    a.hadm_id,
    a.aki_type,
    a.los_group,
    COALESCE(m.mri_ct_count, 0) AS mri_ct_count
  FROM aki_los_grouped a
  LEFT JOIN mri_ct_orders m
    ON a.subject_id = m.subject_id AND a.hadm_id = m.hadm_id
  WHERE a.los_group IS NOT NULL
)
SELECT
  aki_type,
  los_group,
  COUNT(*) AS admission_count,
  ROUND(AVG(mri_ct_count), 2) AS mean_mri_ct_per_admission
FROM final
GROUP BY aki_type, los_group
ORDER BY aki_type, los_group;