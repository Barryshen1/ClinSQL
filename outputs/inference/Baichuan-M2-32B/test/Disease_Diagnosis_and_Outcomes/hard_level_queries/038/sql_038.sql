WITH
  -- Patient demographics and age at admission
  patients_age AS (
    SELECT 
      p.subject_id,
      EXTRACT(YEAR FROM a.admittime) AS adm_year,
      p.anchor_year - p.anchor_age AS birth_year,
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
  ),
  admissions_filtered AS (
    SELECT 
      a.*,
      pa.age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patients_age pa ON a.subject_id = pa.subject_id
    WHERE pa.age_at_admission BETWEEN 74 AND 84
  ),
  aki_admissions AS (
    SELECT DISTINCT
      a.subject_id,
      a.hadm_id
    FROM admissions_filtered a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE 'N17%' AND d.icd_version = 10
  ),
  control_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id
    FROM admissions_filtered a
    WHERE NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'N17%' 
        AND d.icd_version = 10
    )
  ),
  -- Mortality and ARDS for AKI
  aki_mortality_ards AS (
    SELECT 
      aki.hadm_id,
      CASE WHEN a.deathtime IS NOT NULL 
           AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 
        THEN 1 ELSE 0 END AS died_30d,
      MAX(CASE WHEN d.icd_code = 'J80' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_ards
    FROM aki_admissions aki
    JOIN admissions_filtered a ON aki.hadm_id = a.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON aki.subject_id = d.subject_id AND aki.hadm_id = d.hadm_id
        AND d.icd_code = 'J80' AND d.icd_version = 10
    GROUP BY aki.hadm_id, a.deathtime, a.admittime
  ),
  -- Mortality and ARDS for control
  control_mortality_ards AS (
    SELECT 
      ctrl.hadm_id,
      CASE WHEN a.deathtime IS NOT NULL 
           AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 
        THEN 1 ELSE 0 END AS died_30d,
      MAX(CASE WHEN d.icd_code = 'J80' AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_ards
    FROM control_admissions ctrl
    JOIN admissions_filtered a ON ctrl.hadm_id = a.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON ctrl.subject_id = d.subject_id AND ctrl.hadm_id = d.hadm_id
        AND d.icd_code = 'J80' AND d.icd_version = 10
    GROUP BY ctrl.hadm_id, a.deathtime, a.admittime
  ),
  -- LOS for survivors in AKI
  aki_survivor_los AS (
    SELECT 
      a.hadm_id,
      DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
    FROM aki_admissions aki
    JOIN admissions_filtered a ON aki.hadm_id = a.hadm_id
    WHERE a.deathtime IS NULL
  ),
  -- LOS for survivors in control
  control_survivor_los AS (
    SELECT 
      a.hadm_id,
      DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
    FROM control_admissions ctrl
    JOIN admissions_filtered a ON ctrl.hadm_id = a.hadm_id
    WHERE a.deathtime IS NULL
  ),
  -- First ICU stay per admission for AKI
  aki_icu_stays AS (
    SELECT 
      aki.hadm_id,
      i.stay_id,
      i.intime
    FROM aki_admissions aki
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON aki.subject_id = i.subject_id AND aki.hadm_id = i.hadm_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY aki.hadm_id ORDER BY i.intime) = 1
  ),
  -- First APACHE IV score in the first ICU stay for AKI
  aki_apache_scores AS (
    SELECT 
      a.stay_id,
      a.hadm_id,
      ARRAY_AGG(ce.valuenum ORDER BY ce.charttime LIMIT 1)[OFFSET(0)] AS apache_score
    FROM aki_icu_stays a
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON a.stay_id = ce.stay_id 
      AND ce.itemid = 224739 
      AND ce.valuenum IS NOT NULL
    GROUP BY a.stay_id, a.hadm_id
  ),
  aki_risk_scores AS (
    SELECT hadm_id, apache_score
    FROM aki_apache_scores
  ),
  -- Similarly for control
  control_icu_stays AS (
    SELECT 
      ctrl.hadm_id,
      i.stay_id,
      i.intime
    FROM control_admissions ctrl
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON ctrl.subject_id = i.subject_id AND ctrl.hadm_id = i.hadm_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ctrl.hadm_id ORDER BY i.intime) = 1
  ),
  control_apache_scores AS (
    SELECT 
      a.stay_id,
      a.hadm_id,
      ARRAY_AGG(ce.valuenum ORDER BY ce.charttime LIMIT 1)[OFFSET(0)] AS apache_score
    FROM control_icu_stays a
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON a.stay_id = ce.stay_id 
      AND ce.itemid = 224739 
      AND ce.valuenum IS NOT NULL
    GROUP BY a.stay_id, a.hadm_id
  ),
  control_risk_scores AS (
    SELECT hadm_id, apache_score
    FROM control_apache_scores
  ),
  -- Aggregate AKI cohort (only ICU patients for risk score)
  aki_cohort_summary AS (
    SELECT 
      COUNT(*) AS aki_count,
      APPROX_QUANTILES(r.apache_score, 100)[OFFSET(50)] AS median_risk,
      APPROX_QUANTILES(r.apache_score, 100)[OFFSET(25)] AS q1_risk,
      APPROX_QUANTILES(r.apache_score, 100)[OFFSET(75)] AS q3_risk,
      AVG(m.died_30d) AS mortality_rate,
      AVG(m.has_ards) AS ards_rate,
      APPROX_QUANTILES(s.los_days, 100)[OFFSET(50)] AS median_los,
      APPROX_QUANTILES(s.los_days, 100)[OFFSET(25)] AS q1_los,
      APPROX_QUANTILES(s.los_days, 100)[OFFSET(75)] AS q3_los
    FROM aki_mortality_ards m
    LEFT JOIN aki_survivor_los s ON m.hadm_id = s.hadm_id
    LEFT JOIN aki_risk_scores r ON m.hadm_id = r.hadm_id
    WHERE r.apache_score IS NOT NULL  -- only ICU patients for risk score
  ),
  control_cohort_summary AS (
    SELECT 
      COUNT(*) AS control_count,
      APPROX_QUANTILES(r.apache_score, 100)[OFFSET(50)] AS median_risk,
      AVG(m.has_ards) AS ards_rate,
      APPROX_QUANTILES(s.los_days, 100)[OFFSET(50)] AS median_los,
      APPROX_QUANTILES(s.los_days, 100)[OFFSET(25)] AS q1_los,
      APPROX_QUANTILES(s.los_days, 100)[OFFSET(75)] AS q3_los
    FROM control_mortality_ards m
    LEFT JOIN control_survivor_los s ON m.hadm_id = s.hadm_id
    LEFT JOIN control_risk_scores r ON m.hadm_id = r.hadm_id
    WHERE r.apache_score IS NOT NULL
  ),
  -- Risk percentile: percentile of AKI cohort's median risk in control cohort's risk scores
  risk_percentile AS (
    SELECT 
      (COUNT(CASE WHEN apache_score <= aki_median_risk THEN 1 END) * 100.0) / COUNT(*) AS percentile
    FROM control_risk_scores
    CROSS JOIN (SELECT median_risk AS aki_median_risk FROM aki_cohort_summary) aki
  )
-- Final output
SELECT 
  aki_count,
  median_risk,
  q1_risk,
  q3_risk,
  mortality_rate,
  ards_rate AS aki_ards_rate,
  median_los AS aki_median_los,
  q1_los AS aki_q1_los,
  q3_los AS aki_q3_los,
  control_count,
  ards_rate AS control_ards_rate,
  median_los AS control_median_los,
  q1_los AS control_q1_los,
  q3_los AS control_q3_los,
  percentile AS risk_percentile
FROM aki_cohort_summary a
CROSS JOIN control_cohort_summary c
CROSS JOIN risk_percentile r;