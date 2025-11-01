WITH DVT_COHORT AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      LOWER(ddi.long_title) LIKE '%deep vein thrombosis%'
      OR LOWER(ddi.long_title) LIKE '%deep venous thrombosis%'
      OR LOWER(ddi.long_title) LIKE '%venous thrombosis%'
      OR LOWER(ddi.long_title) LIKE '%thrombosis%'
    )
),

-- 2) Comorbidity flags per subject (proxy for comorbidity burden)
COMORBIDITY_FLAGS AS (
  SELECT di.subject_id,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%hypertension%' THEN 1 ELSE 0 END) AS has_hypertension,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%kidney%' OR LOWER(ddi.long_title) LIKE '%nephropathy%' OR LOWER(ddi.long_title) LIKE '%ckd%' THEN 1 ELSE 0 END) AS has_ckd,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%heart failure%' OR LOWER(ddi.long_title) LIKE '%ischemic heart%' OR LOWER(ddi.long_title) LIKE '%coronary%' THEN 1 ELSE 0 END) AS has_heart_failure,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%copd%' OR LOWER(ddi.long_title) LIKE '%lung%' THEN 1 ELSE 0 END) AS has_pulm_disease,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%liver%' THEN 1 ELSE 0 END) AS has_liver_disease,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%cancer%' OR LOWER(ddi.long_title) LIKE '%malignancy%' THEN 1 ELSE 0 END) AS has_cancer,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%stroke%' THEN 1 ELSE 0 END) AS has_stroke,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%dementia%' OR LOWER(ddi.long_title) LIKE '%alzheimer%' THEN 1 ELSE 0 END) AS has_neuro,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%obesity%' THEN 1 ELSE 0 END) AS has_obesity,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%anemia%' THEN 1 ELSE 0 END) AS has_anemia
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  GROUP BY di.subject_id
),

-- 3) Combined comorbidity score per subject (within DVT cohort)
COMORBIDITY_PER_SUBJ AS (
  SELECT c.subject_id,
         -- sum of binary comorbidity flags (per-subject)
         COALESCE(MAX(c.has_diabetes), 0) +
         COALESCE(MAX(c.has_hypertension), 0) +
         COALESCE(MAX(c.has_ckd), 0) +
         COALESCE(MAX(c.has_heart_failure), 0) +
         COALESCE(MAX(c.has_pulm_disease), 0) +
         COALESCE(MAX(c.has_liver_disease), 0) +
         COALESCE(MAX(c.has_cancer), 0) +
         COALESCE(MAX(c.has_stroke), 0) +
         COALESCE(MAX(c.has_neuro), 0) +
         COALESCE(MAX(c.has_obesity), 0) +
         COALESCE(MAX(c.has_anemia), 0) AS comorbidity_score
  FROM COMORBIDITY_FLAGS c
  JOIN DVT_COHORT d ON d.subject_id = c.subject_id
  GROUP BY c.subject_id
),

-- 4) 75th percentile threshold for comorbidity burden
P75_COMORBIDITY AS (
  SELECT quantiles[OFFSET(75)] AS p75
  FROM (
    SELECT APPROX_QUANTILES(comorbidity_score, 100) AS quantiles
    FROM COMORBIDITY_PER_SUBJ
  )
),

-- 5) Major complications per admission (composite)
MAJOR_COMPLICATIONS AS (
  SELECT di.subject_id, di.hadm_id,
         MAX(CASE
               WHEN LOWER(ddi.long_title) LIKE '%sepsis%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%shock%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%acute kidney injury%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%kidney failure%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%myocardial infarction%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%stroke%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%pulmonary embolism%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%pneumonia%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%liver failure%' THEN 1
               WHEN LOWER(ddi.long_title) LIKE '%respiratory failure%' THEN 1
               ELSE 0
             END) AS major_comp
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  GROUP BY di.subject_id, di.hadm_id
),

-- 6) Final per-admission rows for subjects above the 75th comorbidity threshold
FINAL AS (
  SELECT d.subject_id,
         d.hadm_id,
         a.admittime,
         a.deathtime,
         a.dischtime,
         COALESCE(r.comorbidity_score, 0) AS risk_score,
         COALESCE(m.major_comp, 0) AS major_comp
  FROM DVT_COHORT d
  JOIN COMORBIDITY_PER_SUBJ r ON d.subject_id = r.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  CROSS JOIN P75_COMORBIDITY p75
  LEFT JOIN MAJOR_COMPLICATIONS m ON d.subject_id = m.subject_id AND d.hadm_id = m.hadm_id
  WHERE r.comorbidity_score > p75.p75
)

SELECT
  -- Cohort size
  (SELECT COUNT(DISTINCT subject_id) FROM FINAL) AS cohort_size,

  -- 30-day mortality rate
  (SELECT AVG(CASE WHEN died_30d = 1 THEN 1 ELSE 0 END)
   FROM (
     SELECT
       CASE WHEN (TIMESTAMP_DIFF(ad.deathtime, ad.admittime, DAY) <= 30) THEN 1 ELSE 0 END AS died_30d,
       f.subject_id
     FROM FINAL f
     JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
       ON f.subject_id = ad.subject_id AND f.hadm_id = ad.hadm_id
   )) AS day30_mortality_rate,

  -- Major complication rate
  (SELECT AVG(major_comp)
   FROM FINAL) AS major_complication_rate,

  -- Median survival days for decedents (admission-to-death)
  (SELECT median_survival_days
   FROM (
     SELECT quantiles[OFFSET(50)] AS median_survival_days
     FROM (
       SELECT APPROX_QUANTILES(days_to_death, 100) AS quantiles
       FROM (
         SELECT TIMESTAMP_DIFF(ad.deathtime, ad.admittime, DAY) AS days_to_death
         FROM FINAL f
         JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
           ON f.subject_id = ad.subject_id AND f.hadm_id = ad.hadm_id
         WHERE ad.deathtime IS NOT NULL
       )
     )
   )
  ) AS median_survival_days,

  -- Risk score quartiles distribution
  (SELECT ARRAY_AGG(STRUCT(q AS quartile, cnt AS count) ORDER BY quartile)
     FROM (
       SELECT quartile, COUNT(*) AS cnt
       FROM (
         SELECT NTILE(4) OVER (ORDER BY risk_score) AS quartile, risk_score
         FROM FINAL
       )
       GROUP BY quartile
     )
  ) AS risk_quartile_counts;