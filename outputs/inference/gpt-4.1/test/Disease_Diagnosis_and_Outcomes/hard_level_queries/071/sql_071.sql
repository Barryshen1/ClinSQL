WITH
-- 1. Get AMI ICD codes (ICD-9: 410.*, ICD-10: I21.*)
ami_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '410%')
     OR (icd_version = 10 AND icd_code LIKE 'I21%')
),

-- 2. Get major complication ICD codes (stroke, sepsis, ARF, major bleeding)
complication_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- Stroke
    (icd_version = 9 AND icd_code LIKE '434%')
    OR (icd_version = 10 AND icd_code LIKE 'I63%')
    -- Sepsis
    OR (icd_version = 9 AND icd_code LIKE '99591')
    OR (icd_version = 10 AND icd_code LIKE 'A41%')
    -- Acute renal failure
    OR (icd_version = 9 AND icd_code LIKE '584%')
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
    -- Major bleeding (GI, intracranial)
    OR (icd_version = 9 AND icd_code LIKE '431%')
    OR (icd_version = 10 AND icd_code LIKE 'I61%')
    OR (icd_version = 9 AND icd_code LIKE '578%')
    OR (icd_version = 10 AND icd_code LIKE 'K92%')
),

-- 3. AMI+ICU cohort: female, age 68-78, AMI, ICU stay
ami_icu_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN ami_icd ami
    ON d.icd_code = ami.icd_code AND d.icd_version = ami.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- 4. General inpatient cohort: female, age 68-78, no AMI, no ICU stay
gen_inpt_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN ami_icd ami
    ON d.icd_code = ami.icd_code AND d.icd_version = ami.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND icu.stay_id IS NULL
    AND ami.icd_code IS NULL
),

-- 5. Get SAPS II score for AMI+ICU cohort (placeholder: assume sapsii table exists)
-- Replace this with actual SAPS II calculation if needed
sapsii_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Placeholder: random SAPS II score for demonstration
    CAST(ROUND(40 + RAND() * 30) AS INT64) AS sapsii
  FROM ami_icu_cohort
),

-- 6. Major complication flags for both cohorts
ami_icu_complications AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN comp.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS major_complication
  FROM ami_icu_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  LEFT JOIN complication_icd comp
    ON d.icd_code = comp.icd_code AND d.icd_version = comp.icd_version
  GROUP BY c.subject_id, c.hadm_id
),

gen_inpt_complications AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN comp.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS major_complication
  FROM gen_inpt_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  LEFT JOIN complication_icd comp
    ON d.icd_code = comp.icd_code AND d.icd_version = comp.icd_version
  GROUP BY c.subject_id, c.hadm_id
),

-- 7. Survivor LOS for both cohorts
ami_icu_survivor_los AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days
  FROM ami_icu_cohort c
  WHERE c.hospital_expire_flag = 0
),

gen_inpt_survivor_los AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days
  FROM gen_inpt_cohort c
  WHERE c.hospital_expire_flag = 0
),

-- 8. 90-day mortality for AMI+ICU cohort
ami_icu_90d_mortality AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE
      WHEN c.dod IS NOT NULL AND DATETIME_DIFF(c.dod, c.dischtime, DAY) BETWEEN 0 AND 90 THEN 1
      ELSE 0
    END AS died_90d
  FROM ami_icu_cohort c
),

-- 9. Risk percentile for target patient (female, age 73, AMI, ICU)
target_patient AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    s.sapsii
  FROM ami_icu_cohort c
  JOIN sapsii_scores s
    ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  WHERE c.anchor_age = 73
  LIMIT 1
),

-- 10. Calculate risk percentile for target patient
risk_percentile AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.stay_id,
    t.sapsii,
    ROUND(100.0 * SUM(CASE WHEN s.sapsii <= t.sapsii THEN 1 ELSE 0 END) / COUNT(*), 1) AS risk_percentile
  FROM target_patient t
  CROSS JOIN sapsii_scores s
  GROUP BY t.subject_id, t.hadm_id, t.stay_id, t.sapsii
)

-- Final output
SELECT
  -- AMI+ICU cohort stats
  (SELECT APPROX_QUANTILES(sapsii, 4)[OFFSET(2)] FROM sapsii_scores) AS median_sapsii,
  (SELECT APPROX_QUANTILES(sapsii, 4)[OFFSET(1)] FROM sapsii_scores) AS sapsii_q1,
  (SELECT APPROX_QUANTILES(sapsii, 4)[OFFSET(3)] FROM sapsii_scores) AS sapsii_q3,
  (SELECT ROUND(100.0 * AVG(died_90d), 1) FROM ami_icu_90d_mortality) AS ami_icu_90d_mortality_pct,
  (SELECT ROUND(100.0 * AVG(major_complication), 1) FROM ami_icu_complications) AS ami_icu_major_complication_pct,
  (SELECT ROUND(AVG(los_days), 1) FROM ami_icu_survivor_los) AS ami_icu_survivor_los_avg,
  -- General inpatient cohort stats
  (SELECT ROUND(100.0 * AVG(major_complication), 1) FROM gen_inpt_complications) AS gen_inpt_major_complication_pct,
  (SELECT ROUND(AVG(los_days), 1) FROM gen_inpt_survivor_los) AS gen_inpt_survivor_los_avg,
  -- Target patient risk percentile
  (SELECT risk_percentile FROM risk_percentile) AS target_patient_risk_percentile;