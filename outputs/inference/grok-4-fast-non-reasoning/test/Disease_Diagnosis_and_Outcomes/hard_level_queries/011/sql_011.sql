WITH cohort AS (
  -- Base female patients aged 88-98
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN CAST(88 AS INT64) AND CAST(98 AS INT64)
    AND p.anchor_age IS NOT NULL
),

ami_patients AS (
  -- Patients with AMI diagnosis and ICU stay
  SELECT DISTINCT c.subject_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE d.icd_version = '10'
    AND d.icd_code LIKE 'I21%'
),

creatinine_itemids AS (
  -- Item IDs for serum creatinine
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE category = 'Chemistry'
    AND (itemid = 50912 OR itemid = 50983)  -- Serum Creatinine
),

aki_patients AS (
  -- Patients with AKI proxy (Cr >= 1.5 mg/dL during admission, post-ICU)
  SELECT DISTINCT ap.subject_id
  FROM ami_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ap.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  INNER JOIN creatinine_itemids ci
    ON l.itemid = ci.itemid
  WHERE l.charttime >= i.intime
    AND l.charttime <= a.dischtime
    AND l.valueuom = 'mg/dL'
    AND l.valuenum >= 1.5
),

ards_patients AS (
  -- Patients with ARDS (ICD-10 J80)
  SELECT DISTINCT ap.subject_id
  FROM ami_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ap.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE d.icd_version = '10'
    AND d.icd_code = 'J80'
),

deaths_30d AS (
  -- 30-day mortality: in-hospital or post-discharge within 30 days
  SELECT DISTINCT ap.subject_id
  FROM ami_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ap.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE (a.hospital_expire_flag = 1)
     OR (p.dod IS NOT NULL 
         AND a.dischtime < p.dod 
         AND DATE_DIFF(p.dod, a.dischtime, DAY) <= 30)
),

decedents_survival AS (
  -- Survival days for decedents (from admission to death)
  SELECT a.subject_id, DATE_DIFF(COALESCE(p.dod, a.dischtime), a.admittime, DAY) AS survival_days
  FROM ami_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ap.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE (a.hospital_expire_flag = 1 OR p.dod IS NOT NULL)
    AND COALESCE(p.dod, a.dischtime) > a.admittime  -- Death after admission
)

-- Final aggregates
SELECT 
  COUNT(DISTINCT ap.subject_id) AS cohort_size,
  SAFE_DIVIDE(COUNT(DISTINCT d30.subject_id), COUNT(DISTINCT ap.subject_id)) AS mortality_30d_rate,
  SAFE_DIVIDE(COUNT(DISTINCT aki.subject_id), COUNT(DISTINCT ap.subject_id)) AS aki_rate,
  SAFE_DIVIDE(COUNT(DISTINCT ards.subject_id), COUNT(DISTINCT ap.subject_id)) AS ards_rate,
  (SELECT APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] FROM decedents_survival) AS median_survival_days_decedents,
  'Composite risk percentile unavailable in MIMIC-IV (no standard risk model data)' AS composite_risk_percentile_note
FROM ami_patients ap
LEFT JOIN deaths_30d d30 ON ap.subject_id = d30.subject_id
LEFT JOIN aki_patients aki ON ap.subject_id = aki.subject_id
LEFT JOIN ards_patients ards ON ap.subject_id = ards.subject_id;