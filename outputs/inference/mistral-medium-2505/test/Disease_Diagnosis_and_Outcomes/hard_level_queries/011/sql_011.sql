WITH
-- Define AMI ICD codes (ICD-9 and ICD-10)
ami_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code IN ('410.00', '410.01', '410.02', '410.10', '410.11', '410.12', '410.20', '410.21', '410.22', '410.30', '410.31', '410.32', '410.40', '410.41', '410.42', '410.50', '410.51', '410.52', '410.60', '410.61', '410.62', '410.70', '410.71', '410.72', '410.80', '410.81', '410.82', '410.90', '410.91', '410.92'))
    OR (icd_version = 10 AND icd_code IN ('I21.01', 'I21.02', 'I21.09', 'I21.11', 'I21.19', 'I21.21', 'I21.29', 'I21.3', 'I21.4', 'I21.9', 'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'))
),

-- Define AKI ICD codes
aki_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code IN ('584.5', '584.6', '584.7', '584.8', '584.9'))
    OR (icd_version = 10 AND icd_code IN ('N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9'))
),

-- Define ARDS ICD codes
ards_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code IN ('518.82'))
    OR (icd_version = 10 AND icd_code IN ('J80'))
),

-- Get cohort of female patients aged 88-98 with AMI and ICU stay
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    p.dod,
    TIMESTAMP_DIFF(p.dod, a.admittime, DAY) AS survival_days,
    CASE WHEN p.dod IS NOT NULL THEN 1 ELSE 0 END AS is_deceased,
    CASE WHEN TIMESTAMP_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS died_within_30d
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN ami_codes ac ON d.icd_code = ac.icd_code AND d.icd_version = ac.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),

-- Identify AKI cases in cohort
aki_cases AS (
  SELECT DISTINCT c.subject_id, c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id
  JOIN aki_codes ak ON d.icd_code = ak.icd_code AND d.icd_version = ak.icd_version
),

-- Identify ARDS cases in cohort
ards_cases AS (
  SELECT DISTINCT c.subject_id, c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id
  JOIN ards_codes ar ON d.icd_code = ar.icd_code AND d.icd_version = ar.icd_version
),

-- Calculate SOFA score components (simplified)
sofa_components AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Respiratory component (PaO2/FiO2 ratio)
    MAX(CASE WHEN ce.itemid IN (223834, 223835) THEN ce.valuenum ELSE NULL END) AS pao2,
    MAX(CASE WHEN ce.itemid IN (223830, 223831) THEN ce.valuenum ELSE NULL END) AS fio2,
    -- Platelets
    MAX(CASE WHEN ce.itemid = 51265 THEN ce.valuenum ELSE NULL END) AS platelets,
    -- Bilirubin
    MAX(CASE WHEN ce.itemid = 50885 THEN ce.valuenum ELSE NULL END) AS bilirubin,
    -- Glasgow Coma Scale
    MAX(CASE WHEN ce.itemid = 198 THEN ce.valuenum ELSE NULL END) AS gcs,
    -- Vasopressors
    MAX(CASE WHEN ce.itemid IN (221906, 221907, 221908, 221909) THEN 1 ELSE 0 END) AS vasopressors
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.hadm_id = ce.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

-- Calculate simplified SOFA score (0-24 scale)
sofa_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- Total SOFA score
    CASE
      WHEN pao2 IS NULL OR fio2 IS NULL OR platelets IS NULL OR bilirubin IS NULL OR gcs IS NULL THEN NULL
      ELSE
        CASE
          WHEN (pao2 / fio2) >= 400 THEN 0
          WHEN (pao2 / fio2) >= 300 THEN 1
          WHEN (pao2 / fio2) >= 200 THEN 2
          WHEN (pao2 / fio2) >= 100 THEN 3
          ELSE 4
        END +
        CASE
          WHEN platelets >= 150 THEN 0
          WHEN platelets >= 100 THEN 1
          WHEN platelets >= 50 THEN 2
          WHEN platelets >= 20 THEN 3
          ELSE 4
        END +
        CASE
          WHEN bilirubin < 1.2 THEN 0
          WHEN bilirubin < 2.0 THEN 1
          WHEN bilirubin < 6.0 THEN 2
          WHEN bilirubin < 12.0 THEN 3
          ELSE 4
        END +
        CASE
          WHEN gcs = 15 THEN 0
          WHEN gcs >= 13 THEN 1
          WHEN gcs >= 10 THEN 2
          WHEN gcs >= 6 THEN 3
          ELSE 4
        END +
        COALESCE(vasopressors, 0)
    END AS sofa_score
  FROM sofa_components
),

-- Calculate median survival for decedents
median_survival AS (
  SELECT PERCENTILE_DISC(survival_days, 0.5) AS median_survival_days
  FROM cohort
  WHERE is_deceased = 1
)

-- Final results
SELECT
  -- Cohort characteristics
  COUNT(DISTINCT c.subject_id) AS cohort_size,
  AVG(c.anchor_age) AS avg_age,
  COUNT(DISTINCT c.hadm_id) AS total_admissions,

  -- Composite risk (SOFA score)
  AVG(ss.sofa_score) AS avg_sofa_score,

  -- Outcomes
  SUM(c.died_within_30d) AS deaths_within_30d,
  ROUND(SUM(c.died_within_30d) * 100.0 / COUNT(DISTINCT c.subject_id), 2) AS mortality_30d_rate,
  COUNT(DISTINCT ak.subject_id) AS aki_cases,
  ROUND(COUNT(DISTINCT ak.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id), 2) AS aki_rate,
  COUNT(DISTINCT ar.subject_id) AS ards_cases,
  ROUND(COUNT(DISTINCT ar.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id), 2) AS ards_rate,
  (SELECT median_survival_days FROM median_survival) AS median_survival_days
FROM cohort c
LEFT JOIN sofa_scores ss ON c.subject_id = ss.subject_id AND c.hadm_id = ss.hadm_id
LEFT JOIN aki_cases ak ON c.subject_id = ak.subject_id AND c.hadm_id = ak.hadm_id
LEFT JOIN ards_cases ar ON c.subject_id = ar.subject_id AND c.hadm_id = ar.hadm_id;