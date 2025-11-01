WITH diag_flags AS (
  SELECT
    di.hadm_id,
    MAX(IF(
      -- AMI: text match or common ICD prefixes (ICD-9 410*, ICD-10 I21*)
      (LOWER(COALESCE(dd.long_title, '')) LIKE '%myocardial infarction%'
       OR LOWER(COALESCE(dd.long_title, '')) LIKE '%acute myocardial infarction%'
       OR di.icd_code LIKE '410%' OR di.icd_code LIKE 'I21%'), 1, 0)) AS any_ami,
    MAX(IF(
      -- Shock: any mention of "shock" or common shock code prefixes (ICD-9 785*, ICD-10 R57*)
      (LOWER(COALESCE(dd.long_title, '')) LIKE '%shock%' OR di.icd_code LIKE '785%' OR di.icd_code LIKE 'R57%'), 1, 0)) AS any_shock,
    MAX(IF(
      -- Respiratory failure: text mentions or common code prefixes (ICD-9 518*, ICD-10 J96*)
      (LOWER(COALESCE(dd.long_title, '')) LIKE '%respiratory failure%' OR LOWER(COALESCE(dd.long_title, '')) LIKE '%respiratory insufficiency%'
       OR di.icd_code LIKE '518%' OR di.icd_code LIKE 'J96%'), 1, 0)) AS any_resp_fail,
    MAX(IF(
      -- CKD: chronic kidney disease text or ICD-9 585*, ICD-10 N18*
      (LOWER(COALESCE(dd.long_title, '')) LIKE '%chronic kidney disease%' OR LOWER(COALESCE(dd.long_title, '')) LIKE '%chronic renal%'
       OR di.icd_code LIKE '585%' OR di.icd_code LIKE 'N18%'), 1, 0)) AS any_ckd,
    MAX(IF(
      -- Diabetes: text match or ICD-9 250*, ICD-10 E10*/E11*
      (LOWER(COALESCE(dd.long_title, '')) LIKE '%diabetes%' OR di.icd_code LIKE '250%' OR di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%'), 1, 0)) AS any_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),

cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '<=5' ELSE '>5' END AS los_group,
    df.any_ami,
    df.any_shock,
    df.any_resp_fail,
    df.any_ckd,
    df.any_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN diag_flags df
    ON a.hadm_id = df.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    -- require AMI diagnosis present
    AND COALESCE(df.any_ami, 0) = 1
    -- exclude admissions with any shock or respiratory failure diagnosis
    AND COALESCE(df.any_shock, 0) = 0
    AND COALESCE(df.any_resp_fail, 0) = 0
)

SELECT
  -- counts by LOS group
  SUM(IF(los_group = '<=5', 1, 0)) AS n_le_5,
  SUM(IF(los_group = '>5', 1, 0)) AS n_gt_5,
  -- deaths
  SUM(IF(los_group = '<=5', hospital_expire_flag, 0)) AS deaths_le_5,
  SUM(IF(los_group = '>5', hospital_expire_flag, 0)) AS deaths_gt_5,
  -- mortality rates
  SAFE_DIVIDE(SUM(IF(los_group = '<=5', hospital_expire_flag, 0)), NULLIF(SUM(IF(los_group = '<=5', 1, 0)),0)) AS mort_rate_le_5,
  SAFE_DIVIDE(SUM(IF(los_group = '>5', hospital_expire_flag, 0)), NULLIF(SUM(IF(los_group = '>5', 1, 0)),0)) AS mort_rate_gt_5,
  -- CKD prevalence (counts and proportions)
  SUM(IF(los_group = '<=5', IF(COALESCE(any_ckd,0)=1,1,0), 0)) AS ckd_count_le_5,
  SUM(IF(los_group = '>5', IF(COALESCE(any_ckd,0)=1,1,0), 0)) AS ckd_count_gt_5,
  SAFE_DIVIDE(SUM(IF(los_group = '<=5', IF(COALESCE(any_ckd,0)=1,1,0), 0)), NULLIF(SUM(IF(los_group = '<=5', 1, 0)),0)) AS ckd_prev_le_5,
  SAFE_DIVIDE(SUM(IF(los_group = '>5', IF(COALESCE(any_ckd,0)=1,1,0), 0)), NULLIF(SUM(IF(los_group = '>5', 1, 0)),0)) AS ckd_prev_gt_5,
  -- Diabetes prevalence (counts and proportions)
  SUM(IF(los_group = '<=5', IF(COALESCE(any_diabetes,0)=1,1,0), 0)) AS diab_count_le_5,
  SUM(IF(los_group = '>5', IF(COALESCE(any_diabetes,0)=1,1,0), 0)) AS diab_count_gt_5,
  SAFE_DIVIDE(SUM(IF(los_group = '<=5', IF(COALESCE(any_diabetes,0)=1,1,0), 0)), NULLIF(SUM(IF(los_group = '<=5', 1, 0)),0)) AS diab_prev_le_5,
  SAFE_DIVIDE(SUM(IF(los_group = '>5', IF(COALESCE(any_diabetes,0)=1,1,0), 0)), NULLIF(SUM(IF(los_group = '>5', 1, 0)),0)) AS diab_prev_gt_5,
  -- Absolute and relative mortality differences (gt5 minus le5)
  SAFE_DIVIDE(SUM(IF(los_group = '>5', hospital_expire_flag, 0)), NULLIF(SUM(IF(los_group = '>5', 1, 0)),0))
    - SAFE_DIVIDE(SUM(IF(los_group = '<=5', hospital_expire_flag, 0)), NULLIF(SUM(IF(los_group = '<=5', 1, 0)),0))
    AS absolute_mort_diff_gt5_minus_le5,
  -- Relative risk (mortality rate >5 divided by <=5). NULL if denominator zero.
  CASE
    WHEN SAFE_DIVIDE(SUM(IF(los_group = '<=5', hospital_expire_flag, 0)), NULLIF(SUM(IF(los_group = '<=5', 1, 0)),0)) = 0 THEN NULL
    ELSE SAFE_DIVIDE(SUM(IF(los_group = '>5', hospital_expire_flag, 0)), NULLIF(SUM(IF(los_group = '>5', 1, 0)),0))
         / SAFE_DIVIDE(SUM(IF(los_group = '<=5', hospital_expire_flag, 0)), NULLIF(SUM(IF(los_group = '<=5', 1, 0)),0))
  END AS relative_mort_ratio_gt5_over_le5
FROM cohort;