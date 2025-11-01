WITH patients_age_gender AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE anchor_age BETWEEN 89 AND 99
    AND gender = 'F'
),

septic_shock_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE icd_code IN ('R6520', 'R6521')
    AND icd_version = 10
),

admissions_with_sepsis AS (
  SELECT di.hadm_id, di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN septic_shock_codes ssc ON di.icd_code = ssc.icd_code AND di.icd_version = 10
  INNER JOIN patients_age_gender p ON di.subject_id = p.subject_id
),

cohort_icu AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN patients_age_gender p ON icu.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1 FROM admissions_with_sepsis s 
    WHERE s.hadm_id = icu.hadm_id
  )
),

-- First ICU stay per admission (in case of multiple)
first_icu_stay AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM cohort_icu
),
first_stay AS (
  SELECT * FROM first_icu_stay WHERE rn = 1
),

-- Vitals for qSOFA: SBP, RR, GCS within first 48h of ICU stay
vitals AS (
  SELECT 
    ce.stay_id,
    MIN(CASE WHEN di.label = 'SBP' AND ce.valuenum IS NOT NULL THEN ce.valuenum END) AS sbp_min,
    MAX(CASE WHEN di.label = 'Respiratory Rate' AND ce.valuenum IS NOT NULL THEN ce.valuenum END) AS rr_max,
    MIN(CASE WHEN di.label = 'GCS - Total' AND ce.valuenum IS NOT NULL THEN ce.valuenum END) AS gcs_min
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN first_stay fs ON ce.stay_id = fs.stay_id
  WHERE ce.charttime >= fs.intime 
    AND ce.charttime <= DATETIME_ADD(fs.intime, INTERVAL 48 HOUR)
    AND di.label IN ('SBP', 'Respiratory Rate', 'GCS - Total')
  GROUP BY ce.stay_id
),

-- Compute qSOFA score: 1 point each for SBP <= 100, RR >= 22, GCS < 15
qsofa_scores AS (
  SELECT 
    stay_id,
    CASE WHEN sbp_min IS NOT NULL AND sbp_min <= 100 THEN 1 ELSE 0 END +
    CASE WHEN rr_max IS NOT NULL AND rr_max >= 22 THEN 1 ELSE 0 END +
    CASE WHEN gcs_min IS NOT NULL AND gcs_min < 15 THEN 1 ELSE 0 END AS qsofa_score
  FROM vitals
),

-- Quartiles for qSOFA score
qsofa_quartiles AS (
  SELECT
    APPROX_QUANTILES(qsofa_score, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(qsofa_score, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(qsofa_score, 100)[OFFSET(75)] AS q3
  FROM qsofa_scores
),

-- Abnormal lab frequency in first 48h ICU stay for septic cohort
labs_septic AS (
  SELECT DISTINCT fs.subject_id, 
    MAX(CASE WHEN le.flag = 'abnormal' THEN 1 ELSE 0 END) AS has_abnormal_lab
  FROM first_stay fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON fs.hadm_id = le.hadm_id
  WHERE le.charttime >= fs.intime 
    AND le.charttime <= DATETIME_ADD(fs.intime, INTERVAL 48 HOUR)
  GROUP BY fs.subject_id
),

-- General inpatient cohort (same age/gender) for lab comparison
general_inpatients AS (
  SELECT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions adm
  INNER JOIN patients_age_gender p ON adm.subject_id = p.subject_id
  WHERE NOT EXISTS (
    SELECT 1 FROM admissions_with_sepsis s 
    WHERE s.hadm_id = adm.hadm_id
  )
),

-- First ICU stay for general inpatients (to align time window)
general_icu AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
  INNER JOIN general_inpatients g ON icu.hadm_id = g.hadm_id
),
general_first_stay AS (
  SELECT * FROM general_icu WHERE rn = 1
),

-- Abnormal labs in general cohort within first 48h ICU stay
labs_general AS (
  SELECT DISTINCT gf.subject_id, 
    MAX(CASE WHEN le.flag = 'abnormal' THEN 1 ELSE 0 END) AS has_abnormal_lab
  FROM general_first_stay gf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON gf.hadm_id = le.hadm_id
  WHERE le.charttime >= gf.intime 
    AND le.charttime <= DATETIME_ADD(gf.intime, INTERVAL 48 HOUR)
  GROUP BY gf.subject_id
),

-- Cohort summary: ICU LOS and mortality for septic shock
cohort_summary AS (
  SELECT
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    COUNT(*) AS patient_count
  FROM first_stay
)

-- Final output
SELECT
  'Septic Shock Cohort' AS cohort,
  qq.q1,
  qq.median,
  qq.q3,
  (qq.q3 - qq.q1) AS iqr,
  (SELECT AVG(has_abnormal_lab) FROM labs_septic) AS septic_abnormal_lab_rate,
  (SELECT AVG(has_abnormal_lab) FROM labs_general) AS general_abnormal_lab_rate,
  (SELECT avg_icu_los FROM cohort_summary) AS median_icu_los,
  (SELECT mortality_rate FROM cohort_summary) AS hospital_mortality
FROM qsofa_quartiles qq;