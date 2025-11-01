WITH patient_icu AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    -- Estimate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 40 AND 50
),

systolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%sbp%'
    OR LOWER(label) LIKE '%systolic blood pressure%'
    OR LOWER(abbreviation) = 'sbp'
),

sbp_first_48h AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN systolic_bp_items sbp ON ce.itemid = sbp.itemid
  INNER JOIN patient_icu pi ON ce.stay_id = pi.stay_id
  WHERE ce.charttime >= pi.intime
    AND ce.charttime <= DATETIME_ADD(pi.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude implausible values
  GROUP BY ce.stay_id
),

sbp_categories AS (
  SELECT
    stay_id,
    CASE
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp < 160 THEN '140-159'
      ELSE '>=160'
    END AS sbp_group
  FROM sbp_first_48h
),

mi_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (LOWER(d.long_title) LIKE '%myocardial infarction%'
         OR (di.icd_version = 9 AND di.icd_code = '410')
         OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'I21'))
),

stay_with_outcome AS (
  SELECT
    sc.stay_id,
    sc.sbp_group,
    CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_mi
  FROM sbp_categories sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON sc.stay_id = i.stay_id
  LEFT JOIN mi_diagnoses mi ON i.hadm_id = mi.hadm_id
),

summary AS (
  SELECT
    sbp_group,
    COUNT(*) AS stay_count,
    AVG(CAST(had_mi AS FLOAT64)) AS mi_rate
  FROM stay_with_outcome
  GROUP BY sbp_group
),

totals AS (
  SELECT SUM(stay_count) AS total_stays
  FROM summary
)

SELECT
  s.sbp_group,
  ROUND((s.stay_count / t.total_stays) * 100, 2) AS percent_in_category,
  ROUND(s.mi_rate, 3) AS mi_rate
FROM summary s
CROSS JOIN totals t
ORDER BY s.sbp_group;