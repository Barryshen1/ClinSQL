WITH pneumonia_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),
base_cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND a.hadm_id IN (SELECT hadm_id FROM pneumonia_hadm)
),
diag_weights AS (
  SELECT di.hadm_id,
         CASE
           WHEN LOWER(dd.long_title) LIKE '%myocardial infarction%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%congestive heart failure%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%peripheral vascular disease%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%cerebrovascular%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%dementia%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%chronic pulmonary disease%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%rheumatic%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%peptic ulcer%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%liver disease%' AND
                (LOWER(dd.long_title) LIKE '%moderate%' OR LOWER(dd.long_title) LIKE '%severe%') THEN 3
           WHEN LOWER(dd.long_title) LIKE '%liver disease%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%diabetes%' AND
                (LOWER(dd.long_title) LIKE '%end-organ damage%' OR LOWER(dd.long_title) LIKE '%end organ%') THEN 2
           WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1
           WHEN LOWER(dd.long_title) LIKE '%renal%' OR LOWER(dd.long_title) LIKE '%kidney%' THEN 2
           WHEN LOWER(dd.long_title) LIKE '%cancer%' OR LOWER(dd.long_title) LIKE '%malignancy%' THEN 2
           WHEN LOWER(dd.long_title) LIKE '%metastatic%' AND LOWER(dd.long_title) LIKE '%tumor%' THEN 6
           WHEN LOWER(dd.long_title) LIKE '%leukemia%' THEN 2
           WHEN LOWER(dd.long_title) LIKE '%aids%' OR LOWER(dd.long_title) LIKE '%hiv%' THEN 6
           WHEN LOWER(dd.long_title) LIKE '%moderate liver%' THEN 3
           ELSE 0
         END AS weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM base_cohort)
),
charlson_tbl AS (
  SELECT bc.hadm_id,
         COALESCE(SUM(dw.weight), 0) AS charlson
  FROM base_cohort bc
  LEFT JOIN diag_weights dw ON bc.hadm_id = dw.hadm_id
  GROUP BY bc.hadm_id
),
aki_ards AS (
  SELECT bc.hadm_id,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%acute kidney injury%' OR di.icd_code LIKE '584%' THEN 1 ELSE 0 END) AS aki_present,
         MAX(CASE WHEN LOWER(dd.long_title) LIKE '%acute respiratory distress syndrome%' OR di.icd_code LIKE '518%' OR di.icd_code LIKE 'J80%' THEN 1 ELSE 0 END) AS ards_present
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON bc.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY bc.hadm_id
),
icu_times AS (
  SELECT hadm_id, MIN(intime) AS icu_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
survival_tbl AS (
  SELECT bc.hadm_id,
         CASE WHEN a.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(a.deathtime, ict.icu_intime, DAY) ELSE NULL END AS survival_days
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON bc.hadm_id = a.hadm_id
  LEFT JOIN icu_times ict ON bc.hadm_id = ict.hadm_id
),
data AS (
  SELECT b.hadm_id,
         ct.charlson,
         a.hospital_expire_flag,
         ka.aki_present,
         ka.ards_present,
         st.survival_days
  FROM base_cohort b
  JOIN charlson_tbl ct ON b.hadm_id = ct.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON b.hadm_id = a.hadm_id
  LEFT JOIN aki_ards ka ON b.hadm_id = ka.hadm_id
  LEFT JOIN survival_tbl st ON b.hadm_id = st.hadm_id
),
survival_median AS (
  SELECT PERCENTILE_CONT(survival_days, 0.5) OVER() AS median_survival_days
  FROM data
  WHERE survival_days IS NOT NULL
  LIMIT 1
)
SELECT
  (SELECT COUNT(*) FROM data) AS cohort_size,
  MIN(charlson) AS min_charlson,
  PERCENTILE_CONT(charlson, 0.25) OVER() AS p25_charlson,
  PERCENTILE_CONT(charlson, 0.5) OVER() AS median_charlson,
  PERCENTILE_CONT(charlson, 0.75) OVER() AS p75_charlson,
  MAX(charlson) AS max_charlson,
  -- In-hospital mortality rate
  (SELECT SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) FROM data) AS in_hosp_mortality_rate,
  -- AKI and ARDS rates
  (SELECT SUM(aki_present) / COUNT(*) FROM data) AS aki_rate,
  (SELECT SUM(ards_present) / COUNT(*) FROM data) AS ards_rate,
  -- Median survival days for decedents
  (SELECT median_survival_days FROM survival_median) AS median_survival_days
FROM data
LIMIT 1;