WITH primary_pe AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    p.anchor_age,
    p.gender
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON d.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON d.hadm_id = a.hadm_id
  WHERE
    d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%pulmonary embolism%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
),

-- Charlson Comorbidity Index approximation using ICD codes
-- Simplified version using regex patterns
comorbidities AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(
      CASE
        -- Myocardial infarction
        WHEN LOWER(diag.long_title) LIKE '%myocardial infarction%' THEN 1
        -- Congestive heart failure
        WHEN LOWER(diag.long_title) LIKE '%heart failure%' THEN 1
        -- Peripheral vascular disease
        WHEN LOWER(diag.long_title) LIKE '%peripheral vascular%' THEN 1
        -- Cerebrovascular disease
        WHEN LOWER(diag.long_title) LIKE '%stroke%' OR LOWER(diag.long_title) LIKE '%cerebrovascular%' THEN 1
        -- Dementia
        WHEN LOWER(diag.long_title) LIKE '%dementia%' THEN 1
        -- Chronic pulmonary disease
        WHEN LOWER(diag.long_title) LIKE '%copd%' OR LOWER(diag.long_title) LIKE '%chronic obstructive pulmonary%' THEN 1
        -- Rheumatologic disease
        WHEN LOWER(diag.long_title) LIKE '%rheumatoid arthritis%' THEN 1
        -- Peptic ulcer disease
        WHEN LOWER(diag.long_title) LIKE '%ulcer%' THEN 1
        -- Mild liver disease
        WHEN LOWER(diag.long_title) LIKE '%liver disease%' AND LOWER(diag.long_title) NOT LIKE '%cirrhosis%' THEN 1
        -- Diabetes (without chronic complication)
        WHEN LOWER(diag.long_title) LIKE '%diabetes%' AND LOWER(diag.long_title) NOT LIKE '%complication%' THEN 1
        ELSE 0
      END
    ) AS charlson_score
  FROM
    primary_pe pe
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON pe.hadm_id = dx.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses diag
    ON dx.icd_code = diag.icd_code AND dx.icd_version = diag.icd_version
  GROUP BY
    subject_id, hadm_id
),

-- Add comorbidity score to primary PE patients
pe_with_comorbidity AS (
  SELECT
    pe.*,
    COALESCE(c.charlson_score, 0) AS charlson_score
  FROM
    primary_pe pe
  LEFT JOIN
    comorbidities c
    ON pe.hadm_id = c.hadm_id
),

-- Top quartile of comorbidity burden
top_quartile AS (
  SELECT
    *,
    APPROX_QUANTILES(charlson_score, 4)[OFFSET(3)] AS q3_threshold
  FROM
    pe_with_comorbidity
),

high_comorbidity AS (
  SELECT
    *
  FROM
    top_quartile
  WHERE
    charlson_score >= q3_threshold
),

-- Outcomes
outcomes AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.deathtime,
    h.hospital_expire_flag,
    DATETIME_DIFF(COALESCE(h.deathtime, h.dischtime), h.admittime, DAY) AS survival_days,
    CASE
      WHEN h.deathtime IS NOT NULL AND DATETIME_DIFF(h.deathtime, h.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30_days,
    MAX(
      CASE
        WHEN LOWER(diag.long_title) LIKE '%myocardial infarction%' OR
             LOWER(diag.long_title) LIKE '%arrhythmia%' THEN 1
        ELSE 0
      END
    ) AS cardiac_complication,
    MAX(
      CASE
        WHEN LOWER(diag.long_title) LIKE '%stroke%' OR
             LOWER(diag.long_title) LIKE '%intracranial hemorrhage%' THEN 1
        ELSE 0
      END
    ) AS neurologic_complication
  FROM
    high_comorbidity h
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON h.hadm_id = dx.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses diag
    ON dx.icd_code = diag.icd_code AND dx.icd_version = diag.icd_version
  GROUP BY
    h.subject_id, h.hadm_id, h.admittime, h.dischtime, h.deathtime, h.hospital_expire_flag
)

SELECT
  APPROX_QUANTILES(charlson_score, 100)[OFFSET(75)] AS composite_risk_percentile,
  AVG(died_within_30_days) AS thirty_day_mortality_rate,
  AVG(cardiac_complication) AS cardiac_complication_rate,
  AVG(neurologic_complication) AS neurologic_complication_rate,
  APPROX_MEDIAN(survival_days) AS median_survival_days
FROM
  outcomes;