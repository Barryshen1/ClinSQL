WITH cardiac_arrest AS (
  -- Diagnosis-based (ICD-10 codes for cardiac arrest)
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('I21.4', 'I46.9') AND icd_version = 10
  UNION DISTINCT
  -- Procedure-based (CPR in ICU)
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON p.itemid = di.itemid
  WHERE di.label LIKE '%CPR%' OR di.label LIKE '%cardiopulmonary resuscitation%'
),
icu_stays AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime, 
    i.outtime, 
    i.los,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE (i.subject_id, i.hadm_id) IN (SELECT subject_id, hadm_id FROM cardiac_arrest)
),
patient_info AS (
  SELECT 
    p.subject_id,
    p.anchor_year,
    p.anchor_age,
    -- Approximate birth date: anchor_year - anchor_age
    DATE_ADD(DATE(TIMESTAMP_SECONDS(0)), INTERVAL (p.anchor_year - p.anchor_age - 1970) YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
),
cohort AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    i.deathtime,
    -- Age at ICU admission (approximate)
    TIMESTAMP_DIFF(i.intime, p.birth_date, YEAR) AS age_at_icu,
    -- ICU mortality: 1 if died during ICU stay
    CASE 
      WHEN i.deathtime BETWEEN i.intime AND i.outtime THEN 1 
      ELSE 0 
    END AS icu_mortality
  FROM icu_stays i
  JOIN patient_info p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'  -- Male patients
    AND TIMESTAMP_DIFF(i.intime, p.birth_date, YEAR) BETWEEN 55 AND 65  -- Age 55-65
),
-- Moved after cohort and joined with cohort for time filtering
vital_signs AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    di.itemid,
    di.lownormalvalue,
    di.highnormalvalue
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  JOIN cohort c  -- Join with cohort to access intime
    ON ce.subject_id = c.subject_id 
    AND ce.hadm_id = c.hadm_id 
    AND ce.stay_id = c.stay_id
  WHERE di.itemid IN (211, 442, 443, 220, 676, 223761)  -- Vital signs itemids
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
),
abnormal_vitals AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.stay_id,
    COUNT(CASE 
      WHEN (v.lownormalvalue IS NOT NULL AND v.highnormalvalue IS NOT NULL) 
        AND (v.valuenum < v.lownormalvalue OR v.valuenum > v.highnormalvalue) 
      THEN 1 
    END) AS instability_score
  FROM cohort c
  LEFT JOIN vital_signs v 
    ON c.subject_id = v.subject_id 
    AND c.hadm_id = v.hadm_id 
    AND c.stay_id = v.stay_id
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
final_cohort AS (
  SELECT 
    c.*,
    COALESCE(a.instability_score, 0) AS instability_score  -- Handle NULL as 0
  FROM cohort c
  LEFT JOIN abnormal_vitals a 
    ON c.subject_id = a.subject_id 
    AND c.hadm_id = a.hadm_id 
    AND c.stay_id = a.stay_id
),
top_decile_cutoff AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS cutoff  -- Fixed percentile calculation
  FROM final_cohort
),
top_decile AS (
  SELECT *
  FROM final_cohort
  WHERE instability_score >= (SELECT cutoff FROM top_decile_cutoff)
)
-- Results
SELECT 
  'percentile_70' AS metric,
  (SELECT COUNT(*) FROM final_cohort) AS total_patients,
  (SELECT COUNT(*) FROM final_cohort WHERE instability_score <= 70) AS count_le_70,
  (SELECT COUNT(*) FROM final_cohort WHERE instability_score <= 70) * 100.0 / (SELECT COUNT(*) FROM final_cohort) AS value
UNION ALL
SELECT 
  'mean_los_top_decile',
  NULL,
  NULL,
  (SELECT AVG(los) FROM top_decile)
UNION ALL
SELECT 
  'mortality_top_decile',
  NULL,
  NULL,
  (SELECT AVG(icu_mortality) FROM top_decile);