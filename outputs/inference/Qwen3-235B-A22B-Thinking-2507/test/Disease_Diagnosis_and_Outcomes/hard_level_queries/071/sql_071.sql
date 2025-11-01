WITH ami_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    -- ICD-9: 410.00-410.91 (acute MI)
    (icd_version = 9 AND icd_code >= '4100' AND icd_code <= '41091')
    OR
    -- ICD-10: I21 and I22 codes (acute MI)
    (icd_version = 10 AND icd_code >= 'I21' AND icd_code < 'I23')
),

-- Calculate age at admission and mortality flags
patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    -- 90-day mortality flag (in-hospital or post-discharge)
    CASE 
      WHEN a.deathtime IS NOT NULL AND DATETIME_DIFF(a.deathtime, a.admittime, DAY) <= 90 THEN 1
      WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, CAST(a.admittime AS DATE), DAY) <= 90 THEN 1
      ELSE 0
    END AS mortality_90d,
    -- Length of stay in days (risk proxy)
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),

-- AMI patients
ami_patients AS (
  SELECT 
    pa.*
  FROM patients_age pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.hadm_id = d.hadm_id
  INNER JOIN ami_icd ami
    ON d.icd_code = ami.icd_code AND d.icd_version = ami.icd_version
  WHERE pa.gender = 'F'  -- Female
),

-- Target cohort: Females 68-78 with AMI and ICU stay
ami_icu_cohort AS (
  SELECT 
    ap.*
  FROM ami_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ap.hadm_id = i.hadm_id
  WHERE ap.age_at_admission BETWEEN 68 AND 78
),

-- Comparison cohort: Age-matched general inpatients (same age/gender range)
general_cohort AS (
  SELECT 
    pa.*
  FROM patients_age pa
  WHERE pa.gender = 'F'
    AND pa.age_at_admission BETWEEN 68 AND 78
    AND pa.hadm_id NOT IN (SELECT hadm_id FROM ami_patients)  -- Exclude AMI patients
)

-- Final analysis
SELECT
  'AMI_ICU' AS cohort,
  COUNT(*) AS n,
  -- Median risk score (LOS as proxy) with IQR
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_risk_score,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS q1_risk_score,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS q3_risk_score,
  -- 90-day mortality
  AVG(mortality_90d) AS mortality_90d_rate,
  -- Major complication rate (using heart failure as proxy)
  (SELECT COUNT(DISTINCT d.hadm_id) 
   FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
   WHERE d.hadm_id IN (SELECT hadm_id FROM ami_icu_cohort)
     AND d.icd_code IN ('I50', 'I500', 'I501', 'I509')
  ) / COUNT(*) AS complication_rate,
  -- Survivor LOS
  APPROX_QUANTILES(IF(mortality_90d = 0, los, NULL), 100)[OFFSET(50)] AS survivor_los_median,
  -- Risk percentile (where AMI_ICU median LOS falls in general cohort distribution)
  (SELECT 
     COUNTIF(g.los < a.median_los) * 100.0 / COUNT(*) 
   FROM general_cohort g, 
        (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los 
         FROM ami_icu_cohort) a
  ) AS risk_percentile
FROM ami_icu_cohort;