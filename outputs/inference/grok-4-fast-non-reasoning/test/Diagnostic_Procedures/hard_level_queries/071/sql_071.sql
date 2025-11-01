WITH ich_cohort AS (
  -- ICH female patients aged 50-60 with ICU stay
  SELECT 
    DISTINCT p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    c.stay_id,
    c.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_version = CAST('10' AS INT64)
    AND d.icd_code LIKE 'I61%'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id, a.hadm_id ORDER BY c.stay_id) = 1  -- First ICU stay per admission
),

general_cohort AS (
  -- General female ICU patients aged 50-60
  SELECT 
    DISTINCT p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    c.stay_id,
    c.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id, a.hadm_id ORDER BY c.stay_id) = 1
),

ich_procedures AS (
  -- Procedure burden for ICH cohort in first 72h of first ICU stay
  SELECT 
    ic.subject_id,
    ic.hadm_id,
    COALESCE(icu_proc_count, 0) + COALESCE(hosp_proc_count, 0) AS procedure_count
  FROM ich_cohort ic
  LEFT JOIN (
    -- ICU procedures: distinct orderid from procedureevents within 72h
    SELECT 
      pe.subject_id,
      pe.hadm_id,
      pe.stay_id,
      COUNT(DISTINCT pe.orderid) AS icu_proc_count
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
    INNER JOIN ich_cohort ic
      ON pe.subject_id = ic.subject_id 
      AND pe.hadm_id = ic.hadm_id 
      AND pe.stay_id = ic.stay_id
    WHERE di.category = 'Procedures'
      AND pe.starttime IS NOT NULL
      AND pe.starttime >= ic.intime
      AND pe.starttime <= TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    GROUP BY pe.subject_id, pe.hadm_id, pe.stay_id
  ) icu
    ON ic.subject_id = icu.subject_id 
    AND ic.hadm_id = icu.hadm_id 
    AND ic.stay_id = icu.stay_id
  LEFT JOIN (
    -- Hospital procedures: distinct icd_code within 72h of intime
    SELECT 
      pi.subject_id,
      pi.hadm_id,
      COUNT(DISTINCT pi.icd_code) AS hosp_proc_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN ich_cohort ic
      ON pi.subject_id = ic.subject_id AND pi.hadm_id = ic.hadm_id
    WHERE pi.icd_version = CAST('10' AS INT64)
      AND pi.chartdate IS NOT NULL
      AND TIMESTAMP(pi.chartdate) >= ic.intime
      AND TIMESTAMP(pi.chartdate) <= TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    GROUP BY pi.subject_id, pi.hadm_id
  ) hosp
    ON ic.subject_id = hosp.subject_id AND ic.hadm_id = hosp.hadm_id
),

general_procedures AS (
  -- Procedure burden for general cohort (for completeness, though not directly asked)
  SELECT 
    gc.subject_id,
    gc.hadm_id,
    COALESCE(icu_proc_count, 0) + COALESCE(hosp_proc_count, 0) AS procedure_count
  FROM general_cohort gc
  LEFT JOIN (
    -- ICU procedures within 72h
    SELECT 
      pe.subject_id,
      pe.hadm_id,
      pe.stay_id,
      COUNT(DISTINCT pe.orderid) AS icu_proc_count
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
    INNER JOIN general_cohort gc
      ON pe.subject_id = gc.subject_id 
      AND pe.hadm_id = gc.hadm_id 
      AND pe.stay_id = gc.stay_id
    WHERE di.category = 'Procedures'
      AND pe.starttime IS NOT NULL
      AND pe.starttime >= gc.intime
      AND pe.starttime <= TIMESTAMP_ADD(gc.intime, INTERVAL 72 HOUR)
    GROUP BY pe.subject_id, pe.hadm_id, pe.stay_id
  ) icu
    ON gc.subject_id = icu.subject_id 
    AND gc.hadm_id = icu.hadm_id 
    AND gc.stay_id = gc.stay_id
  LEFT JOIN (
    -- Hospital procedures within 72h
    SELECT 
      pi.subject_id,
      pi.hadm_id,
      COUNT(DISTINCT pi.icd_code) AS hosp_proc_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN general_cohort gc
      ON pi.subject_id = gc.subject_id AND pi.hadm_id = gc.hadm_id
    WHERE pi.icd_version = CAST('10' AS INT64)
      AND pi.chartdate IS NOT NULL
      AND TIMESTAMP(pi.chartdate) >= gc.intime
      AND TIMESTAMP(pi.chartdate) <= TIMESTAMP_ADD(gc.intime, INTERVAL 72 HOUR)
    GROUP BY pi.subject_id, pi.hadm_id
  ) hosp
    ON gc.subject_id = hosp.subject_id AND gc.hadm_id = hosp.hadm_id
),

ich_outcomes AS (
  -- LOS and mortality for ICH
  SELECT 
    hadm_id,
    DATE_DIFF(LEAST(dischtime, COALESCE(deathtime, dischtime)), admittime, DAY) AS hospital_los_days,
    hospital_expire_flag
  FROM ich_cohort
),

general_outcomes AS (
  -- LOS and mortality for general cohort
  SELECT 
    hadm_id,
    DATE_DIFF(LEAST(dischtime, COALESCE(deathtime, dischtime)), admittime, DAY) AS hospital_los_days,
    hospital_expire_flag
  FROM general_cohort
)

-- Procedure percentiles for ICH cohort
SELECT 
  'ICH Cohort' AS cohort,
  PERCENTILE_CONT(0.25, 0) OVER() AS p25_procedures,
  PERCENTILE_CONT(0.50, 0) OVER() AS p50_procedures,
  PERCENTILE_CONT(0.90, 0) OVER() AS p90_procedures,
  MAX(procedure_count) AS max_procedures,
  NULL AS avg_los_days,
  NULL AS mortality_rate,
  COUNT(*) AS n_patients
FROM ich_procedures

UNION ALL

-- Outcomes for ICH
SELECT 
  'ICH Cohort' AS cohort,
  NULL AS p25_procedures,
  NULL AS p50_procedures,
  NULL AS p90_procedures,
  NULL AS max_procedures,
  AVG(hospital_los_days) AS avg_los_days,
  AVG(hospital_expire_flag * 1.0) AS mortality_rate,
  COUNT(*) AS n_patients
FROM ich_outcomes

UNION ALL

-- Outcomes for general
SELECT 
  'General ICU Cohort' AS cohort,
  NULL AS p25_procedures,
  NULL AS p50_procedures,
  NULL AS p90_procedures,
  NULL AS max_procedures,
  AVG(hospital_los_days) AS avg_los_days,
  AVG(hospital_expire_flag * 1.0) AS mortality_rate,
  COUNT(*) AS n_patients
FROM general_outcomes;