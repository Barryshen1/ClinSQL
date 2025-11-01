WITH base_cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    p.gender,
    adm.hospital_expire_flag,
    -- Calculate exact age at admission: anchor_age + (admission_year - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 40 AND 50
),
stroke_group AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430', '431', '432'))
    OR 
    (icd_version = 10 AND icd_code IN ('I60', 'I61', 'I62'))
),
procedure_counts AS (
  SELECT 
    b.stay_id,
    COUNT(p.itemid) AS num_procedures  -- Count all procedures within first 72h of ICU stay
  FROM base_cohort b
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON b.stay_id = p.stay_id
    AND p.starttime >= b.intime
    AND p.starttime < DATETIME_ADD(b.intime, INTERVAL 72 HOUR)
  GROUP BY b.stay_id
),
cohort_with_groups AS (
  SELECT 
    b.*,
    COALESCE(pc.num_procedures, 0) AS num_procedures,  -- Include stays with 0 procedures
    CASE 
      WHEN s.hadm_id IS NOT NULL THEN 'Hemorrhagic Stroke'
      ELSE 'Other'
    END AS patient_group
  FROM base_cohort b
  LEFT JOIN stroke_group s
    ON b.hadm_id = s.hadm_id
  LEFT JOIN procedure_counts pc
    ON b.stay_id = pc.stay_id
)
SELECT 
  patient_group,
  COUNT(*) AS total_stays,
  -- 90th percentile of procedure count
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS proc_90th_percentile,
  -- ICU LOS: median and IQR
  APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS los_median,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS los_25th,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS los_75th,
  -- Mortality rate
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_rate_percent
FROM cohort_with_groups
GROUP BY patient_group;