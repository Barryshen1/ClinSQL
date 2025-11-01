WITH sepsis_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'sepsis|septicemia|bacteremia')
),
base_cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    a.hospital_expire_flag,
    CASE WHEN di.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS sepsis_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN sepsis_codes sc
      ON di.icd_code = sc.icd_code AND di.icd_version = sc.icd_version
  ) di
    ON ie.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
),
procedure_counts AS (
  SELECT 
    bc.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON bc.stay_id = pe.stay_id
    AND pe.starttime >= bc.intime
    AND pe.starttime < DATETIME_ADD(bc.intime, INTERVAL 24 HOUR)
  GROUP BY bc.stay_id
),
cohort AS (
  SELECT 
    bc.*,
    COALESCE(pc.procedure_count, 0) AS procedure_count
  FROM base_cohort bc
  LEFT JOIN procedure_counts pc
    ON bc.stay_id = pc.stay_id
),
sepsis_procedure_quantiles AS (
  SELECT 
    APPROX_QUANTILES(procedure_count, 100) AS percentiles
  FROM cohort
  WHERE sepsis_flag = 1
)
SELECT 
  'Sepsis' AS cohort,
  AVG(los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS hospital_mortality_rate,
  (SELECT percentiles[OFFSET(75)] FROM sepsis_procedure_quantiles) AS p75_procedures,
  (SELECT percentiles[OFFSET(90)] FROM sepsis_procedure_quantiles) AS p90_procedures
FROM cohort
WHERE sepsis_flag = 1
UNION ALL
SELECT 
  'Control' AS cohort,
  AVG(los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS hospital_mortality_rate,
  NULL AS p75_procedures,
  NULL AS p90_procedures
FROM cohort
WHERE sepsis_flag = 0;