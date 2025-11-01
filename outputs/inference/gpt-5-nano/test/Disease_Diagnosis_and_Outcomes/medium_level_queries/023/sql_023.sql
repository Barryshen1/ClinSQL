WITH stroke_map AS (
  SELECT
    di.hadm_id,
    MAX(CASE
          WHEN dic.long_title LIKE '%ischemic stroke%' THEN 'ischemic'
          WHEN dic.long_title LIKE '%hemorrhagic stroke%' THEN 'hemorrhagic'
          ELSE NULL
        END) AS stroke_class
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON di.icd_code = dic.icd_code
   AND di.icd_version = dic.icd_version
  WHERE dic.long_title LIKE '%stroke%'
  GROUP BY di.hadm_id
  HAVING MAX(CASE
               WHEN dic.long_title LIKE '%ischemic stroke%' THEN 'ischemic'
               WHEN dic.long_title LIKE '%hemorrhagic stroke%' THEN 'hemorrhagic'
               ELSE NULL
             END) IS NOT NULL
),
stroke_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN stroke_map AS sm
    ON sm.hadm_id = a.hadm_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
    AND sm.stroke_class IS NOT NULL
),
domain_flags AS (
  SELECT di.hadm_id,
         MAX(CASE WHEN dic.long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN dic.long_title LIKE '%chronic kidney disease%' OR dic.long_title LIKE '%kidney%' THEN 1 ELSE 0 END) AS has_ckd,
         MAX(CASE WHEN dic.long_title LIKE '%hypertension%' THEN 1 ELSE 0 END) AS has_htn,
         MAX(CASE WHEN dic.long_title LIKE '%heart failure%' OR dic.long_title LIKE '%myocardial infarction%' THEN 1 ELSE 0 END) AS has_cardio,
         MAX(CASE WHEN dic.long_title LIKE '%cancer%' OR dic.long_title LIKE '%neoplasm%' THEN 1 ELSE 0 END) AS has_cancer,
         MAX(CASE WHEN dic.long_title LIKE '%liver%' THEN 1 ELSE 0 END) AS has_liver,
         MAX(CASE WHEN dic.long_title LIKE '%dementia%' THEN 1 ELSE 0 END) AS has_dementia,
         MAX(CASE WHEN dic.long_title LIKE '%COPD%' OR dic.long_title LIKE '%chronic obstructive pulmonary disease%' THEN 1 ELSE 0 END) AS has_copd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON di.icd_code = dic.icd_code
   AND di.icd_version = dic.icd_version
  GROUP BY di.hadm_id
),
base AS (
  SELECT sa.hadm_id,
         sm.stroke_class,
         TIMESTAMP_DIFF(sa.dischtime, sa.admittime, DAY) AS los_days,
         sa.hospital_expire_flag AS mortality,
         IFNULL(df.has_ckd, 0) AS has_ckd,
         IFNULL(df.has_diabetes, 0) AS has_diabetes,
         IFNULL(df.has_htn, 0) AS has_htn,
         IFNULL(df.has_cardio, 0) AS has_cardio,
         IFNULL(df.has_cancer, 0) AS has_cancer,
         IFNULL(df.has_liver, 0) AS has_liver,
         IFNULL(df.has_dementia, 0) AS has_dementia,
         IFNULL(df.has_copd, 0) AS has_copd,
         (IFNULL(df.has_diabetes,0) + IFNULL(df.has_ckd,0) + IFNULL(df.has_htn,0) +
          IFNULL(df.has_cardio,0) + IFNULL(df.has_cancer,0) + IFNULL(df.has_liver,0) +
          IFNULL(df.has_dementia,0) + IFNULL(df.has_copd,0)) AS comorbidity_count
  FROM stroke_admissions sa
  LEFT JOIN domain_flags df ON df.hadm_id = sa.hadm_id
  LEFT JOIN stroke_map sm ON sm.hadm_id = sa.hadm_id
),
with_tert AS (
  SELECT *,
         NTILE(3) OVER (ORDER BY comorbidity_count) AS comorb_tert
  FROM base
)
SELECT
  stroke_class,
  comorb_tert AS comorbidity_tertile,
  AVG(mortality) * 100 AS in_hospital_mortality_pct,
  -- Use approximate median via quantiles (2 quantiles -> median)
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  100.0 * SUM(CASE WHEN los_days < 8 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_lt8,
  100.0 * SUM(CASE WHEN los_days >= 8 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_ge8,
  AVG(has_ckd) * 100 AS ckd_prev_pct,
  AVG(has_diabetes) * 100 AS diabetes_prev_pct
FROM with_tert
GROUP BY stroke_class, comorb_tert
ORDER BY stroke_class, comorbidity_tertile;