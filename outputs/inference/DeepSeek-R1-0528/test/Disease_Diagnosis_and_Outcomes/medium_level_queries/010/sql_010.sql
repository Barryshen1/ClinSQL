WITH base_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '410%') 
        OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
    )
    AND adm.hadm_id NOT IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        ( -- Shock
          (icd_version = 9 AND icd_code LIKE '7855%') 
          OR (icd_version = 10 AND icd_code LIKE 'R57%')
        ) 
        OR ( -- Respiratory Failure
          (icd_version = 9 AND icd_code IN ('51881','51882','51884','51885')) 
          OR (icd_version = 10 AND icd_code LIKE 'J96%')
        )
    )
),

comorbidity_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code LIKE '585%') 
      OR (icd_version = 10 AND (
        icd_code LIKE 'N18%' OR icd_code LIKE 'I12%' OR 
        icd_code LIKE 'I13%' OR icd_code = 'N19' OR 
        icd_code LIKE 'N25%' OR icd_code LIKE 'Z49%' OR 
        icd_code LIKE 'Z94%' OR icd_code LIKE 'Z99%'
      )) THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code LIKE '250%') 
      OR (icd_version = 10 AND (
        icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR 
        icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR 
        icd_code LIKE 'E14%'
      )) THEN 1 ELSE 0 END) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

comorbidity_count AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT category) AS comorbidity_count
  FROM (
    SELECT 
      diag.hadm_id,
      CASE
        WHEN diag.icd_version = 9 THEN
          CASE 
            WHEN diag.icd_code LIKE '398%' OR diag.icd_code LIKE '402%' OR diag.icd_code LIKE '425%' OR diag.icd_code LIKE '428%' THEN 'Heart_Failure'
            WHEN diag.icd_code LIKE '440%' OR diag.icd_code LIKE '441%' OR diag.icd_code IN ('4439', '7854', 'V434') OR diag.icd_code BETWEEN '0930' AND '0932' OR diag.icd_code IN ('4373', '4471', '5571', '5579', 'V415') THEN 'PVD'
            -- Add other Charlson mappings here (abbreviated for brevity)
            ELSE NULL
          END
        WHEN diag.icd_version = 10 THEN
          CASE 
            WHEN diag.icd_code LIKE 'I43%' OR diag.icd_code LIKE 'I50%' OR diag.icd_code LIKE 'I099' OR diag.icd_code IN ('I110', 'I130', 'I132', 'I255', 'I420', 'I425', 'I426', 'I427', 'I428', 'P290') THEN 'Heart_Failure'
            WHEN diag.icd_code LIKE 'I70%' OR diag.icd_code LIKE 'I71%' OR diag.icd_code IN ('I731', 'I738', 'I739', 'I771', 'I790', 'I792', 'K551', 'K558', 'K559', 'Z958', 'Z959') THEN 'PVD'
            -- Add other Charlson mappings here
            ELSE NULL
          END
      END AS category
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE 
      NOT ( -- Exclude AMI codes to avoid double-counting
        (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
        OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
      )
  )
  WHERE category IS NOT NULL
  GROUP BY hadm_id
),

cohort_with_features AS (
  SELECT 
    bc.*,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
    COALESCE(cf.ckd_flag, 0) AS ckd_flag,
    COALESCE(cf.diabetes_flag, 0) AS diabetes_flag,
    CASE 
      WHEN COALESCE(cc.comorbidity_count, 0) = 0 THEN 'low'
      WHEN COALESCE(cc.comorbidity_count, 0) <= 2 THEN 'medium'
      ELSE 'high'
    END AS comorbidity_burden
  FROM base_cohort bc
  LEFT JOIN comorbidity_flags cf ON bc.hadm_id = cf.hadm_id
  LEFT JOIN comorbidity_count cc ON bc.hadm_id = cc.hadm_id
),

cohort_with_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY los_hospital) AS los_quartile
  FROM cohort_with_features
)

SELECT 
  los_quartile,
  comorbidity_burden,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(hospital_expire_flag) - 1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*)) AS ci_lower,
  AVG(hospital_expire_flag) + 1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*)) AS ci_upper,
  AVG(ckd_flag) AS ckd_prevalence,
  AVG(diabetes_flag) AS diabetes_prevalence
FROM cohort_with_quartiles
GROUP BY los_quartile, comorbidity_burden
ORDER BY los_quartile, comorbidity_burden;