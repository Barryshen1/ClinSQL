WITH ich_cohort AS (
  -- First ICU stay for female patients aged 50-60 with primary ICH (ICD-10 I61*)
  WITH filtered_icu AS (
    SELECT 
      icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime, icu.outtime, icu.los,
      pat.gender, pat.anchor_age,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON icu.subject_id = diag.subject_id AND icu.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
      AND pat.anchor_age BETWEEN 50 AND 60
      AND diag.icd_version = '10'
      AND diag.icd_code LIKE 'I61%'
      AND diag.seq_num = CAST(1 AS INT64)  -- Primary diagnosis
  )
  SELECT * FROM filtered_icu
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
),

procedure_burden AS (
  -- Count all procedure events in first 72h for ICH cohort (total burden)
  SELECT 
    ich.stay_id,
    COUNT(*) AS proc_count  -- Count events, not distinct itemids, for burden
  FROM ich_cohort ich
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON ich.stay_id = proc.stay_id
    AND proc.starttime >= ich.intime
    AND proc.starttime < TIMESTAMP_ADD(ich.intime, INTERVAL 72 HOUR)
    AND proc.itemid IS NOT NULL
  GROUP BY ich.stay_id
),

general_icu AS (
  -- Aggregates for all ICU stays (comparator)
  SELECT 
    AVG(los) AS general_avg_los,
    COUNTIF(adm.hospital_expire_flag = CAST(1 AS INT64)) / COUNT(*) AS general_mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
)

SELECT 
  -- Procedure percentiles for ICH cohort
  PERCENTILE_CONT(0.25) OVER() AS p25_proc_count,
  PERCENTILE_CONT(0.50) OVER() AS p50_proc_count,
  PERCENTILE_CONT(0.90) OVER() AS p90_proc_count,
  
  -- ICH cohort aggregates
  AVG(burden.proc_count) AS ich_avg_proc_count,  -- For reference
  AVG(ich.los) AS ich_avg_los,
  AVG(CASE WHEN ich.hospital_expire_flag = CAST(1 AS INT64) THEN 1.0 ELSE 0 END) AS ich_mortality_rate,
  
  -- General ICU
  gen.general_avg_los,
  gen.general_mortality_rate

FROM procedure_burden burden
INNER JOIN ich_cohort ich ON burden.stay_id = ich.stay_id
CROSS JOIN general_icu gen;