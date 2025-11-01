WITH
-- primary diagnosis descriptions joined to diagnoses
diag_long AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    LOWER(det.long_title) AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` det
  ON
    d.icd_code = det.icd_code
    AND d.icd_version = det.icd_version
),

-- identify admissions that are primary-postoperative-complication
postop_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  -- restrict to males age 51-61 (anchor_age)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    -- primary diagnosis must match postoperative complication phrasing
    AND EXISTS (
      SELECT 1
      FROM diag_long dl
      JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
        ON dl.hadm_id = d2.hadm_id AND dl.subject_id = d2.subject_id
      WHERE
        dl.hadm_id = a.hadm_id
        -- ensure it's the primary diagnosis (seq_num = 1)
        AND d2.seq_num = 1
        AND (
          -- common phrasings for postoperative complication; regex to be permissive
          REGEXP_CONTAINS(dl.long_title, r'postoperat.*complic')
          OR REGEXP_CONTAINS(dl.long_title, r'complic.*postoperat')
          OR REGEXP_CONTAINS(dl.long_title, r'complication of.*procedure')
          OR REGEXP_CONTAINS(dl.long_title, r'postoperative complication')
        )
    )
),

-- gather all diagnosis descriptions for each admission (for comorbidities and condition flags)
hadm_all_dx AS (
  SELECT
    d.hadm_id,
    LOWER(det.long_title) AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` det
  ON
    d.icd_code = det.icd_code
    AND d.icd_version = det.icd_version
  WHERE
    d.hadm_id IN (SELECT hadm_id FROM postop_admissions)
),

-- compute approximate Charlson score weights per admission using keyword-based detection
hadm_charlson AS (
  SELECT
    hadm_id,

    -- Simple presence flags for conditions (1 if present, else 0)
    MAX(IF(REGEXP_CONTAINS(long_title, r'myocardial infarction|myocardial infarct|acute myocardial'), 1, 0)) AS f_mi,
    MAX(IF(REGEXP_CONTAINS(long_title, r'congestive heart|heart failure'), 1, 0)) AS f_chf,
    MAX(IF(REGEXP_CONTAINS(long_title, r'peripheral vascular|peripheral artery|peripheral vascular disease'), 1, 0)) AS f_pvd,
    MAX(IF(REGEXP_CONTAINS(long_title, r'cerebrovascular|stroke|transient ischemic attack'), 1, 0)) AS f_cvd,
    MAX(IF(REGEXP_CONTAINS(long_title, r'dementia'), 1, 0)) AS f_dementia,
    MAX(IF(REGEXP_CONTAINS(long_title, r'chronic obstructive pulmonary|copd|emphysema|chronic bronchitis'), 1, 0)) AS f_copd,
    MAX(IF(REGEXP_CONTAINS(long_title, r'rheumatoid|systemic lupus|lupus|scleroderma|connective tissue'), 1, 0)) AS f_connective,
    MAX(IF(REGEXP_CONTAINS(long_title, r'peptic ulcer|peptic ulcer disease|gastric ulcer|duodenal ulcer'), 1, 0)) AS f_peptic,

    -- liver: mild vs severe detection (approx)
    MAX(IF(REGEXP_CONTAINS(long_title, r'cirrhosis|chronic liver|alcoholic liver'), 1, 0)) AS f_liver_mild_like,
    MAX(IF(REGEXP_CONTAINS(long_title, r'portal hypertension|esophageal varices|hepatic failure|severe liver|liver failure'), 1, 0)) AS f_liver_severe_like,

    -- diabetes: detect complicated vs uncomplicated
    MAX(IF(REGEXP_CONTAINS(long_title, r'diabetes.*with|diabetes.*complic|diabetic.*(nephropathy|retinopathy|neuropathy|ulcer|angiopath)'), 1, 0)) AS f_dm_with_comp,
    MAX(IF(REGEXP_CONTAINS(long_title, r'\bdiabetes\b|\bdiabetes mellitus\b|\bdiabetic\b'), 1, 0)) AS f_dm_any,

    MAX(IF(REGEXP_CONTAINS(long_title, r'hemiplegia|paraplegia|paraparesis|quadriplegia'), 1, 0)) AS f_hemiplegia,
    MAX(IF(REGEXP_CONTAINS(long_title, r'chronic kidney|chronic renal|renal failure|kidney failure|end stage renal|esrd|end-stage renal'), 1, 0)) AS f_renal,
    MAX(IF(REGEXP_CONTAINS(long_title, r'metastatic|secondary malignant|secondary neoplasm|secondary malignant neoplasm'), 1, 0)) AS f_metastatic,
    MAX(IF(REGEXP_CONTAINS(long_title, r'malignant neoplasm|malignant neoplasm|carcinoma|cancer'), 1, 0)) AS f_malignancy,
    MAX(IF(REGEXP_CONTAINS(long_title, r'leukemia|lymphoma'), 1, 0)) AS f_leukemia_lymphoma,
    MAX(IF(REGEXP_CONTAINS(long_title, r'\bhiv\b|aids'), 1, 0)) AS f_aids

  FROM hadm_all_dx
  GROUP BY hadm_id
),

-- turn those flags into Charlson weighted score (approximate)
hadm_charlson_score AS (
  SELECT
    hadm_id,
    (
      -- weights per Charlson index (approximate):
      -- MI 1, CHF 1, PVD 1, CVD 1, dementia 1, COPD 1, connective tissue 1, peptic ulcer 1,
      -- mild liver 1, severe liver 3 (we only approximate; treat severe as 3),
      -- diabetes without complication 1, diabetes with complication 2,
      -- hemiplegia 2, renal disease 2, malignancy 2, metastatic 3, leukemia/lymphoma 2, AIDS 6
      IF(f_mi = 1, 1, 0)
      + IF(f_chf = 1, 1, 0)
      + IF(f_pvd = 1, 1, 0)
      + IF(f_cvd = 1, 1, 0)
      + IF(f_dementia = 1, 1, 0)
      + IF(f_copd = 1, 1, 0)
      + IF(f_connective = 1, 1, 0)
      + IF(f_peptic = 1, 1, 0)
      + IF(f_liver_severe_like = 1, 3, IF(f_liver_mild_like = 1, 1, 0))
      + CASE
          WHEN f_dm_with_comp = 1 THEN 2
          WHEN f_dm_any = 1 THEN 1
          ELSE 0
        END
      + IF(f_hemiplegia = 1, 2, 0)
      + IF(f_renal = 1, 2, 0)
      + IF(f_metastatic = 1, 3, 0)
      + IF(f_leukemia_lymphoma = 1, 2, 0)
      + IF(f_aids = 1, 6, 0)
      -- malignancy without metastasis (if present and metastasis not present)
      + IF(f_malignancy = 1 AND f_metastatic = 0 AND f_leukemia_lymphoma = 0, 2, 0)
    ) AS charlson_score,

    -- also produce CKD and diabetes flags for prevalence reporting
    IF(f_renal = 1, 1, 0) AS has_ckd,
    CASE
      WHEN f_dm_with_comp = 1 THEN 1
      WHEN f_dm_any = 1 THEN 1
      ELSE 0
    END AS has_diabetes

  FROM hadm_charlson
),

-- assemble admission-level dataset with LOS, ICU flag, charlson category and condition flags
admission_metrics AS (
  SELECT
    pa.hadm_id,
    pa.subject_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    -- LOS in days (count partial day as 1)
    DATE_DIFF(DATE(pa.dischtime), DATE(pa.admittime), DAY) + 1 AS los_days,
    -- ICU flag: whether there is any icustay for this hadm_id
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = pa.hadm_id
    ) THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    -- Charlson score and category
    COALESCE(hcs.charlson_score, 0) AS charlson_score,
    CASE
      WHEN COALESCE(hcs.charlson_score, 0) <= 1 THEN '0-1'
      WHEN COALESCE(hcs.charlson_score, 0) = 2 THEN '2'
      ELSE '>=3'
    END AS charlson_cat,
    COALESCE(hcs.has_ckd, 0) AS has_ckd,
    COALESCE(hcs.has_diabetes, 0) AS has_diabetes
  FROM postop_admissions pa
  LEFT JOIN hadm_charlson_score hcs
  ON pa.hadm_id = hcs.hadm_id
)

-- Final aggregation: stratify by ICU vs Non-ICU, LOS bin, Charlson category
SELECT
  am.icu_status,
  CASE
    WHEN am.los_days BETWEEN 1 AND 2 THEN '1-2'
    WHEN am.los_days BETWEEN 3 AND 5 THEN '3-5'
    WHEN am.los_days BETWEEN 6 AND 9 THEN '6-9'
    ELSE '>=10'
  END AS los_bin,
  am.charlson_cat AS charlson_category,
  COUNT(1) AS n_admissions,
  -- mortality percent
  ROUND(100.0 * SUM(CAST(am.hospital_expire_flag AS INT64)) / COUNT(1), 1) AS mortality_percent,
  -- approximate median LOS using APPROX_QUANTILES
  -- use bucket 100 and take the 50th percentile (offset 50)
  CAST( (APPROX_QUANTILES(am.los_days, 100))[OFFSET(50)] AS INT64 ) AS median_los_days,
  -- CKD prevalence %
  ROUND(100.0 * SUM(am.has_ckd) / COUNT(1), 1) AS ckd_prevalence_percent,
  -- Diabetes prevalence %
  ROUND(100.0 * SUM(am.has_diabetes) / COUNT(1), 1) AS diabetes_prevalence_percent
FROM
  admission_metrics am
GROUP BY
  icu_status,
  los_bin,
  charlson_category
ORDER BY
  icu_status DESC,  -- ICU first
  los_bin,
  charlson_category;