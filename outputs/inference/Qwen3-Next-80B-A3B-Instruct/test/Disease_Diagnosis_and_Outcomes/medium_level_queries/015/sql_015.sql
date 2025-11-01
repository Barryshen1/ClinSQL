WITH stroke_admissions AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS in_icu,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COUNT(DISTINCT CASE 
      WHEN d.long_title NOT LIKE '%stroke%' 
        AND d.long_title NOT LIKE '%cerebrovascular%' 
        AND d.long_title NOT LIKE '%infarction%' 
        AND d.long_title NOT LIKE '%hemorrhage%' 
        AND NOT (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
        AND NOT (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
        AND (
          d.long_title LIKE '%heart failure%' 
          OR d.long_title LIKE '%hypertension%' 
          OR d.long_title LIKE '%diabetes%' 
          OR d.long_title LIKE '%chronic kidney disease%' 
          OR d.long_title LIKE '%chronic obstructive pulmonary disease%' 
          OR d.long_title LIKE '%liver disease%' 
          OR d.long_title LIKE '%cancer%' 
          OR d.long_title LIKE '%metastatic cancer%' 
          OR d.long_title LIKE '%paralysis%' 
          OR d.long_title LIKE '%psychoses%' 
          OR d.long_title LIKE '%depression%' 
          OR d.long_title LIKE '%anemia%' 
          OR d.long_title LIKE '%coagulopathy%' 
          OR d.long_title LIKE '%obesity%' 
          OR d.long_title LIKE '%weight loss%' 
          OR d.long_title LIKE '%fluid overload%' 
          OR d.long_title LIKE '%lymphoma%' 
          OR d.long_title LIKE '%melanoma%' 
          OR d.long_title LIKE '%other neoplasm%'
        )
      THEN d.icd_code 
    END) AS comorbidity_count
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      d.long_title LIKE '%stroke%' 
      OR d.long_title LIKE '%cerebrovascular%' 
      OR d.long_title LIKE '%infarction%' 
      OR d.long_title LIKE '%hemorrhage%'
      OR (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
    )
  GROUP BY p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, i.stay_id
),
aggregated AS (
  SELECT
    in_icu,
    CASE WHEN los_days <= 5 THEN 'LOS ≤5' ELSE 'LOS >5' END AS los_category,
    COUNT(*) AS total_admissions,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) AS mortality_rate,
    -- 95% CI: p ± 1.96 * sqrt(p*(1-p)/n)
    1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*)) AS ci_margin,
    AVG(comorbidity_count) AS avg_comorbidity_count
  FROM stroke_admissions
  GROUP BY in_icu, CASE WHEN los_days <= 5 THEN 'LOS ≤5' ELSE 'LOS >5' END
)
SELECT
  CASE WHEN in_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS admission_type,
  los_category,
  total_admissions,
  deaths,
  ROUND(100 * mortality_rate, 2) AS mortality_percent,
  ROUND(100 * (mortality_rate - ci_margin), 2) AS ci_lower,
  ROUND(100 * (mortality_rate + ci_margin), 2) AS ci_upper,
  ROUND(avg_comorbidity_count, 1) AS avg_comorbidity_count
FROM aggregated
ORDER BY admission_type, los_category;