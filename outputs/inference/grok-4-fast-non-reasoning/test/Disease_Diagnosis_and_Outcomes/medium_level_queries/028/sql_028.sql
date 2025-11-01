WITH hf_cohort AS (
  -- Identify admissions with HF diagnosis
  SELECT DISTINCT 
    ad.subject_id,
    ad.hadm_id,
    ad.admittime,
    ad.dischtime,
    ad.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ad.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.subject_id = diag.subject_id AND ad.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN SAFE_CAST('43' AS INT64) AND SAFE_CAST('53' AS INT64)
    AND (
      (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '428%') OR
      (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'I50%')
    )
    AND ad.dischtime IS NOT NULL
    AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) > 0  -- Exclude zero-day stays
),

comorb AS (
  -- Proxy for comorbidity burden: count distinct diagnosis categories (exclude HF)
  SELECT 
    hc.*,
    COUNT(DISTINCT 
      CASE 
        WHEN NOT (
          (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '428%') OR
          (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'I50%')
        ) THEN 
          CASE 
            WHEN diag.icd_version = 'ICD-9' THEN SUBSTR(diag.icd_code, 1, 3)
            ELSE SUBSTR(diag.icd_code, 1, 3)
          END
      END
    ) AS comorb_count,
    CASE 
      WHEN COUNT(DISTINCT 
        CASE 
          WHEN NOT (
            (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '428%') OR
            (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'I50%')
          ) THEN 
            CASE 
              WHEN diag.icd_version = 'ICD-9' THEN SUBSTR(diag.icd_code, 1, 3)
              ELSE SUBSTR(diag.icd_code, 1, 3)
            END
        END
      ) <= 2 THEN 'low'
      WHEN COUNT(DISTINCT 
        CASE 
          WHEN NOT (
            (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '428%') OR
            (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'I50%')
          ) THEN 
            CASE 
              WHEN diag.icd_version = 'ICD-9' THEN SUBSTR(diag.icd_code, 1, 3)
              ELSE SUBSTR(diag.icd_code, 1, 3)
            END
        END
      ) BETWEEN 3 AND 5 THEN 'medium'
      ELSE 'high'
    END AS comorbidity_group
  FROM hf_cohort hc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON hc.subject_id = diag.subject_id AND hc.hadm_id = diag.hadm_id
  GROUP BY 
    hc.subject_id, hc.hadm_id, hc.admittime, hc.dischtime, hc.hospital_expire_flag,
    hc.gender, hc.anchor_age, hc.los
),

stratified AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY los) AS los_quartile,
    CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END AS mortality_flag
  FROM comorb
)

SELECT 
  los_quartile,
  comorbidity_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(mortality_flag) * 100, 2) AS mortality_pct
FROM stratified
GROUP BY los_quartile, comorbidity_group
ORDER BY los_quartile, 
  CASE comorbidity_group 
    WHEN 'low' THEN 1 
    WHEN 'medium' THEN 2 
    WHEN 'high' THEN 3 
  END;