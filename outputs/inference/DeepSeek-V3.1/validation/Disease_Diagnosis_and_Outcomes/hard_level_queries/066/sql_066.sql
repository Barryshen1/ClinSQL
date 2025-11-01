WITH
-- Cohort of male patients aged 81-91 with PE
pe_cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.dod,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
      OR (di.icd_version = 9 AND di.icd_code = '4151')
    )
),

-- Compute comorbidity score: number of distinct ICD chapters
comorbidity_scores AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN di.icd_version = 10 THEN SUBSTR(di.icd_code, 1, 1)
        WHEN di.icd_version = 9 THEN SUBSTR(di.icd_code, 1, 3)
      END
    ) AS comorbidity_count
  FROM pe_cohort p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON p.hadm_id = di.hadm_id
  GROUP BY p.subject_id, p.hadm_id
),

-- Compute 75th percentile of comorbidity_count for the cohort
percentile75 AS (
  SELECT
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS p75
  FROM comorbidity_scores
),

-- Filter cohort to high comorbidity
high_comorb_pe_cohort AS (
  SELECT
    c.*,
    cs.comorbidity_count
  FROM pe_cohort c
  INNER JOIN comorbidity_scores cs
    ON c.hadm_id = cs.hadm_id
  CROSS JOIN percentile75 p
  WHERE cs.comorbidity_count > p.p75
),

-- Calculate 90-day mortality
mortality_90d AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 THEN 1
      ELSE 0
    END AS died_90d
  FROM high_comorb_pe_cohort
),

-- AKI and ARDS diagnoses
aki_ards AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN (icd_version = 10 AND icd_code LIKE 'N17%') OR (icd_version = 9 AND icd_code LIKE '584%') THEN 1 ELSE 0 END) AS aki,
    MAX(CASE WHEN (icd_version = 10 AND icd_code = 'J80') OR (icd_version = 9 AND icd_code = '51882') THEN 1 ELSE 0 END) AS ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- Combine for final cohort
cohort_with_outcomes AS (
  SELECT
    h.*,
    m.died_90d,
    COALESCE(a.aki, 0) AS aki,
    COALESCE(a.ards, 0) AS ards,
    DATE_DIFF(DATE(h.dischtime), DATE(h.admittime), DAY) AS los
  FROM high_comorb_pe_cohort h
  LEFT JOIN mortality_90d m
    ON h.hadm_id = m.hadm_id
  LEFT JOIN aki_ards a
    ON h.hadm_id = a.hadm_id
),

-- For all inpatients
all_inpatients AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.anchor_age,
    p.gender,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

-- Comorbidity score for all inpatients (simplified)
all_inpatients_comorb AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN di.icd_version = 10 THEN SUBSTR(di.icd_code, 1, 1)
        WHEN di.icd_version = 9 THEN SUBSTR(di.icd_code, 1, 3)
      END
    ) AS comorbidity_count
  FROM all_inpatients a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  GROUP BY a.hadm_id
),

-- Percentile of the mean comorbidity count of our cohort in all inpatients
cohort_mean_comorb AS (
  SELECT AVG(comorbidity_count) AS mean_comorb
  FROM high_comorb_pe_cohort
),
all_inpatients_percentile AS (
  SELECT
    (SELECT COUNT(*) FROM all_inpatients_comorb WHERE comorbidity_count <= (SELECT mean_comorb FROM cohort_mean_comorb))
    / (SELECT COUNT(*) FROM all_inpatients_comorb) * 100 AS percentile
)

-- Main results
SELECT
  (SELECT AVG(comorbidity_count) FROM high_comorb_pe_cohort) AS mean_risk_score,
  (SELECT AVG(died_90d) FROM cohort_with_outcomes) * 100 AS mortality_90d_percent,
  (SELECT AVG(aki) FROM cohort_with_outcomes) * 100 AS aki_rate,
  (SELECT AVG(ards) FROM cohort_with_outcomes) * 100 AS ards_rate,
  (SELECT AVG(los) FROM cohort_with_outcomes WHERE hospital_expire_flag = 0) AS mean_los_survivors,
  (SELECT AVG(los) FROM all_inpatients WHERE hospital_expire_flag = 0) AS mean_los_all_inpatients_survivors,
  (SELECT percentile FROM all_inpatients_percentile) AS matched_profile_risk_percentile;