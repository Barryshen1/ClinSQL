WITH base_cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    pt.gender,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admission,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
        WHERE icu.hadm_id = adm.hadm_id
      ) THEN TRUE 
      ELSE FALSE 
    END AS had_icu,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 48 AND 58
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(430|431|432|433|434|435|436|437|438)')) OR
        (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(I6[0-9]|G45|G46)'))
    )
),

comorbidity_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(428|398\.91|402\.01|402\.11|402\.91|404\.01|404\.03|404\.11|404\.13|404\.91|404\.93)')) OR
               (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(I50|I11\.0|I13\.0|I13\.2)')) 
          THEN 1 ELSE 0 
        END) AS chf_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250')) OR
               (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[0-4]')) 
          THEN 1 ELSE 0 
        END) AS dm_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

cohort_with_comorbidity AS (
  SELECT 
    bc.*,
    cf.chf_flag,
    cf.dm_flag,
    cf.chf_flag + cf.dm_flag AS comorbidity_count
  FROM base_cohort bc
  LEFT JOIN comorbidity_flags cf
    ON bc.hadm_id = cf.hadm_id
)

SELECT 
  group_type,
  group_name,
  n,
  mortality_count,
  mortality_percentage,
  mortality_percentage - 1.96 * ci_width AS ci_lower,
  mortality_percentage + 1.96 * ci_width AS ci_upper
FROM (
  -- ICU grouping
  SELECT 
    'ICU' AS group_type,
    CASE WHEN had_icu THEN 'ICU' ELSE 'non-ICU' END AS group_name,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS mortality_count,
    (SUM(hospital_expire_flag) / COUNT(*)) * 100 AS mortality_percentage,
    SQRT((SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*)) * 100 AS ci_width
  FROM cohort_with_comorbidity
  GROUP BY group_name

  UNION ALL

  -- LOS grouping
  SELECT 
    'LOS' AS group_type,
    CASE WHEN los_days <= 5 THEN '<=5' ELSE '>5' END AS group_name,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS mortality_count,
    (SUM(hospital_expire_flag) / COUNT(*)) * 100 AS mortality_percentage,
    SQRT((SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*)) * 100 AS ci_width
  FROM cohort_with_comorbidity
  GROUP BY group_name

  UNION ALL

  -- Comorbidity grouping
  SELECT 
    'Comorbidity' AS group_type,
    CAST(comorbidity_count AS STRING) AS group_name,  -- Cast to string for consistent type
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS mortality_count,
    (SUM(hospital_expire_flag) / COUNT(*)) * 100 AS mortality_percentage,
    SQRT((SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*)) * 100 AS ci_width
  FROM cohort_with_comorbidity
  GROUP BY comorbidity_count
)
ORDER BY group_type, group_name;