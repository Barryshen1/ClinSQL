WITH cohort AS (
  -- Base cohort: female admissions aged 39-49 with HF diagnosis
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- CKD and diabetes flags (index admission only)
    MAX(CASE WHEN di.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN di.icd_code LIKE 'E1[0-4]%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
    AND di.icd_version = 10
    AND di.icd_code LIKE 'I50%'  -- Heart failure
  GROUP BY 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.gender, p.anchor_age
),

comorb_counts AS (
  -- Patient-level chronic comorbidity count (historical, excluding HF)
  SELECT 
    subject_id,
    COUNT(DISTINCT comorb_group) AS num_comorb
  FROM (
    SELECT DISTINCT
      d.subject_id,
      CASE 
        WHEN d.icd_code LIKE 'I10%' OR d.icd_code LIKE 'I1[1-6]%' THEN 'HTN'
        WHEN d.icd_code LIKE 'E1[0-4]%' THEN 'DM'
        WHEN d.icd_code LIKE 'N18%' THEN 'CKD'
        WHEN d.icd_code LIKE 'J4[0-7]%' THEN 'COPD'
        WHEN d.icd_code LIKE 'I2[0-5]%' THEN 'CAD'
        WHEN d.icd_code LIKE 'I6[0-9]%' THEN 'STROKE'
        WHEN d.icd_code LIKE 'C[0-9][0-9]%' OR d.icd_code LIKE 'D[0-4][0-9]%' THEN 'CANCER'
        WHEN d.icd_code LIKE 'F0[1-3]%' THEN 'DEMENTIA'
        ELSE NULL
      END AS comorb_group
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE 
      d.icd_version = 10
      AND d.icd_code NOT LIKE 'I50%'  -- Exclude HF itself
      AND CASE 
        WHEN d.icd_code LIKE 'I10%' OR d.icd_code LIKE 'I1[1-6]%' THEN 'HTN'
        WHEN d.icd_code LIKE 'E1[0-4]%' THEN 'DM'
        WHEN d.icd_code LIKE 'N18%' THEN 'CKD'
        WHEN d.icd_code LIKE 'J4[0-7]%' THEN 'COPD'
        WHEN d.icd_code LIKE 'I2[0-5]%' THEN 'CAD'
        WHEN d.icd_code LIKE 'I6[0-9]%' THEN 'STROKE'
        WHEN d.icd_code LIKE 'C[0-9][0-9]%' OR d.icd_code LIKE 'D[0-4][0-9]%' THEN 'CANCER'
        WHEN d.icd_code LIKE 'F0[1-3]%' THEN 'DEMENTIA'
        ELSE NULL
      END IS NOT NULL
  )
  GROUP BY subject_id
),

stratified AS (
  SELECT 
    c.*,
    COALESCE(cc.num_comorb, 0) AS num_comorb,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_group,
    NTILE(3) OVER (ORDER BY COALESCE(cc.num_comorb, 0)) AS comorb_tertile_num
  FROM 
    cohort c
  LEFT JOIN 
    comorb_counts cc
    ON c.subject_id = cc.subject_id
)

SELECT 
  los_group,
  CASE 
    WHEN comorb_tertile_num = 1 THEN 'Low'
    WHEN comorb_tertile_num = 2 THEN 'Med'
    ELSE 'High'
  END AS comorb_tertile,
  COUNT(hadm_id) AS N,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM 
  stratified
GROUP BY 
  los_group, comorb_tertile_num
ORDER BY 
  los_group, comorb_tertile_num;