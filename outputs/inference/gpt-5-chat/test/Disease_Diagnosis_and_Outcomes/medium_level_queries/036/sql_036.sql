WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '428%')  -- ICD-9 HF
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 HF
        )
    )
),
comorb_flags AS (
  SELECT
    ha.subject_id,
    ha.hadm_id,
    COUNT(DISTINCT di.icd_code) AS comorb_count,
    -- CKD flag
    MAX(CASE
          WHEN (di.icd_version = 9 AND di.icd_code LIKE '585%')
            OR (di.icd_version = 10 AND di.icd_code LIKE 'N18%')
          THEN 1 ELSE 0 END) AS flag_ckd,
    -- Diabetes flag
    MAX(CASE
          WHEN (di.icd_version = 9 AND di.icd_code LIKE '250%')
            OR (di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%'))
          THEN 1 ELSE 0 END) AS flag_dm
  FROM hf_admissions ha
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ha.hadm_id = di.hadm_id
    AND NOT (
      (di.icd_version = 9 AND di.icd_code LIKE '428%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    ) -- exclude HF diagnosis itself
  GROUP BY ha.subject_id, ha.hadm_id
),
tertiled AS (
  SELECT
    ha.*,
    cf.comorb_count,
    cf.flag_ckd,
    cf.flag_dm,
    NTILE(3) OVER (ORDER BY cf.comorb_count) AS comorb_tertile,
    CASE WHEN ha.los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group
  FROM hf_admissions ha
  JOIN comorb_flags cf
    ON ha.subject_id = cf.subject_id
    AND ha.hadm_id = cf.hadm_id
)
SELECT
  los_group,
  CASE comorb_tertile WHEN 1 THEN 'Low' WHEN 2 THEN 'Medium' WHEN 3 THEN 'High' END AS comorb_tertile,
  COUNT(*) AS N,
  ROUND(100 * AVG(hospital_expire_flag), 1) AS mortality_percent,
  ROUND(100 * AVG(flag_ckd), 1) AS ckd_percent,
  ROUND(100 * AVG(flag_dm), 1) AS dm_percent
FROM tertiled
GROUP BY los_group, comorb_tertile
ORDER BY los_group, comorb_tertile;