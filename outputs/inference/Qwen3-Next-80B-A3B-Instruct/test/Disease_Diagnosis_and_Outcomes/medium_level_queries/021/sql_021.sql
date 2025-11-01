WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p 
    ON a.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.services s 
    ON a.hadm_id = s.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i 
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND s.curr_service IN ('SURG', 'CARDSURG', 'NEUROSURG', 'THORAC', 'VASC', 'ORTHO', 'URO', 'GYNEC', 'ENT', 'OPHTHAL', 'PLASTIC', 'MAXFAC')
    AND s.transfertime >= a.admittime
    AND s.transfertime <= a.dischtime
),

charlson_conditions AS (
  SELECT DISTINCT
    d.subject_id,
    CASE 
      WHEN d.long_title LIKE '%myocardial infarction%' THEN 'MI'
      WHEN d.long_title LIKE '%congestive heart failure%' THEN 'CHF'
      WHEN d.long_title LIKE '%peripheral vascular disease%' THEN 'PVD'
      WHEN d.long_title LIKE '%cerebrovascular disease%' THEN 'CVA'
      WHEN d.long_title LIKE '%dementia%' THEN 'Dementia'
      WHEN d.long_title LIKE '%chronic pulmonary disease%' THEN 'COPD'
      WHEN d.long_title LIKE '%rheumatic disease%' OR d.long_title LIKE '%connective tissue%' THEN 'Connective Tissue'
      WHEN d.long_title LIKE '%renal disease%' THEN 'Renal'
      WHEN d.long_title LIKE '%diabetes%' AND d.long_title NOT LIKE '%diabetes with complications%' THEN 'Diabetes'
      WHEN d.long_title LIKE '%diabetes with complications%' THEN 'DiabetesComp'
      WHEN d.long_title LIKE '%hepatic disease%' THEN 'Hepatic'
      WHEN d.long_title LIKE '%tumor%' OR d.long_title LIKE '%cancer%' OR d.long_title LIKE '%malignancy%' THEN 'Cancer'
      WHEN d.long_title LIKE '%metastatic cancer%' THEN 'Metastatic Cancer'
      WHEN d.long_title LIKE '%aids%' THEN 'AIDS'
      ELSE NULL
    END AS charlson_condition
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE d.subject_id IN (SELECT subject_id FROM cohort)
),

charlson_score AS (
  SELECT 
    subject_id,
    COUNT(charlson_condition) AS charlson_score
  FROM charlson_conditions
  WHERE charlson_condition IS NOT NULL
  GROUP BY subject_id
),

final_cohort AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.is_icu,
    c.los_days,
    COALESCE(cs.charlson_score, 0) AS charlson_score,
    CASE 
      WHEN c.hospital_expire_flag = 1 THEN EXTRACT(DAY FROM (c.deathtime - c.admittime))
      ELSE NULL
    END AS time_to_death_days
  FROM cohort c
  LEFT JOIN charlson_score cs ON c.subject_id = cs.subject_id
)

SELECT
  is_icu,
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    WHEN los_days >= 8 THEN '≥8 days'
    ELSE 'Unknown'
  END AS los_category,
  CASE 
    WHEN charlson_score <= 3 THEN '≤3'
    WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
    WHEN charlson_score > 5 THEN '>5'
    ELSE 'Unknown'
  END AS charlson_category,
  COUNT(*) AS N,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  MEDIAN(time_to_death_days) AS median_time_to_death_days
FROM final_cohort
GROUP BY is_icu, los_category, charlson_category
ORDER BY is_icu, los_category, charlson_category;