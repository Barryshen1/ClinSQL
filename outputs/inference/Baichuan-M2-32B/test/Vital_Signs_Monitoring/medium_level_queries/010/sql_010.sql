WITH patients_with_birth AS (
  SELECT 
    subject_id,
    gender,
    anchor_year,
    anchor_age,
    DATE(anchor_year - anchor_age, 1, 1) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
icu_stays_with_age AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.intime, p.birth_date, YEAR) AS age_at_icu,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_with_birth p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(i.intime, p.birth_date, YEAR) BETWEEN 77 AND 87
),
bp_measurements AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    ce.valuenum AS systolic_bp
  FROM icu_stays_with_age i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON i.subject_id = ce.subject_id 
    AND i.hadm_id = ce.hadm_id 
    AND i.stay_id = ce.stay_id
    AND ce.itemid IN (51, 442089)  -- Corrected itemids for systolic BP
    AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    AND ce.valuenum BETWEEN 50 AND 250
),
stay_avg_bp AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    AVG(systolic_bp) AS avg_sbp
  FROM bp_measurements
  GROUP BY subject_id, hadm_id, stay_id
)
SELECT 
  SAFE_DIVIDE(100.0 * COUNTIF(avg_sbp <= 160), COUNT(*)) AS percentile
FROM stay_avg_bp;