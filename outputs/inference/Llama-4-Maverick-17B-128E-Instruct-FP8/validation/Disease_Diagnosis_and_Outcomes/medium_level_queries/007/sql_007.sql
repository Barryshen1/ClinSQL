WITH 
-- Step 1: Identify heart failure patients and filter by age and gender
heart_failure_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, di.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diags ON p.subject_id = diags.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON diags.icd_code = di.icd_code AND diags.icd_version = di.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 51 AND 61
  AND di.long_title LIKE '%Heart failure%'
),

-- Step 2: Determine ICU stay and LOS for each admission
icu_stays AS (
  SELECT hadm_id, COUNT(stay_id) AS icu_stay_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
admissions_info AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         a.hospital_expire_flag,
         COALESCE(icu.icu_stay_count, 0) > 0 AS had_icu_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN icu_stays icu ON a.hadm_id = icu.hadm_id
),

-- Step 3: Calculate comorbidity burden
comorbidity_burden AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- Step 4: Identify MV, Vaso, RRT usage
procedure_events AS (
  SELECT DISTINCT pe.hadm_id,
         MAX(CASE WHEN di.label LIKE '%Mechanical Ventilation%' THEN 1 ELSE 0 END) AS had_mv,
         MAX(CASE WHEN di.label LIKE '%Vasopressor%' THEN 1 ELSE 0 END) AS had_vaso,
         MAX(CASE WHEN di.label LIKE '%Renal Replacement Therapy%' THEN 1 ELSE 0 END) AS had_rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  GROUP BY pe.hadm_id
)

-- Final query to report in-hospital mortality rates and prevalence
SELECT 
  ai.had_icu_stay,
  ai.los < 8 AS los_less_than_8,
  CASE 
    WHEN cb.num_diagnoses <= 3 THEN 'low'
    WHEN cb.num_diagnoses <= 6 THEN 'med'
    ELSE 'high'
  END AS comorbidity_burden,
  COUNT(*) AS total_patients,
  SUM(ai.hospital_expire_flag) AS in_hospital_deaths,
  SUM(ai.hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_rate,
  AVG(pe.had_mv) AS mv_prevalence,
  AVG(pe.had_vaso) AS vaso_prevalence,
  AVG(pe.had_rrt) AS rrt_prevalence
FROM heart_failure_patients hfp
JOIN admissions_info ai ON hfp.subject_id = ai.hadm_id
JOIN comorbidity_burden cb ON ai.hadm_id = cb.hadm_id
LEFT JOIN procedure_events pe ON ai.hadm_id = pe.hadm_id
GROUP BY ai.had_icu_stay, ai.los < 8, comorbidity_burden
ORDER BY ai.had_icu_stay, ai.los < 8, comorbidity_burden;