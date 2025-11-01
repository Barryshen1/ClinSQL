WITH first_icu_stays AS (
  -- Get first ICU stay per subject_id
  SELECT 
    subject_id,
    stay_id,
    hadm_id,
    intime,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE intime IS NOT NULL
),
patient_cohorts AS (
  -- Base cohort: females aged 53-63 with first ICU stay
  SELECT 
    fis.*,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fis.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fis.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND fis.rn = 1
),
sepsis_cohorts AS (
  -- Flag sepsis vs non-sepsis using aggregation
  SELECT 
    pc.*,
    MAX(CASE 
      WHEN di.icd_code LIKE 'A41%' OR di.icd_code LIKE 'R65%' THEN 1 
      ELSE 0 
    END) AS has_sepsis
  FROM patient_cohorts pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pc.hadm_id = di.hadm_id
    AND di.icd_version = 'ICD-10'  -- Focus on ICD-10 for modern sepsis codes
  GROUP BY 
    pc.subject_id, pc.stay_id, pc.hadm_id, pc.intime, pc.los, 
    pc.gender, pc.anchor_age, pc.hospital_expire_flag
),
procedure_counts AS (
  -- Count distinct procedures in first 24h per patient (LEFT JOIN handles 0s)
  SELECT 
    sc.subject_id,
    sc.stay_id,
    sc.has_sepsis,
    sc.los,
    sc.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM sepsis_cohorts sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON sc.subject_id = pe.subject_id
    AND sc.hadm_id = pe.hadm_id
    AND sc.stay_id = pe.stay_id
    AND pe.starttime >= sc.intime
    AND pe.starttime < TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)
    AND pe.itemid IS NOT NULL  -- Valid procedures
  GROUP BY sc.subject_id, sc.stay_id, sc.has_sepsis, sc.los, sc.hospital_expire_flag
)
-- Final aggregations: percentiles for procedures, avg LOS and mortality
SELECT 
  CASE WHEN has_sepsis = 1 THEN 'Sepsis' ELSE 'Non-Sepsis (Age-matched)' END AS cohort,
  -- Procedure percentiles
  PERCENTILE_CONT(num_procedures, 0.75) AS p75_procedures,
  PERCENTILE_CONT(num_procedures, 0.90) AS p90_procedures,
  -- Outcomes (aggregated across cohort)
  AVG(los) AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS avg_hospital_mortality_pct,
  COUNT(DISTINCT subject_id) AS num_patients
FROM procedure_counts
GROUP BY has_sepsis
ORDER BY has_sepsis DESC;