WITH cohort_stays AS (
  -- First ICU stays for male patients aged 60-70 with principal ICH diagnosis
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    hospital_expire_flag
  FROM (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.los,
      a.hospital_expire_flag,
      p.gender,
      p.anchor_age,
      ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn_first_stay
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON i.hadm_id = d.hadm_id
    WHERE 
      i.first_careunit IS NOT NULL
      AND p.gender = 'M'
      AND p.anchor_age BETWEEN 60 AND 70
      AND d.seq_num = 1  -- Principal diagnosis
      AND (
        (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
        OR
        (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I61%')
      )
  )
  WHERE rn_first_stay = 1
),

procedure_burden AS (
  -- Count distinct procedures in first 72h for cohort
  SELECT 
    cs.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM 
    cohort_stays cs
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON cs.subject_id = pe.subject_id
    AND cs.hadm_id = pe.hadm_id
    AND CAST(cs.stay_id AS STRING) = pe.stay_id
    AND pe.starttime >= cs.intime
    AND pe.starttime <= DATETIME_ADD(cs.intime, INTERVAL 72 HOUR)
    AND EXTRACT(HOUR FROM (pe.starttime - cs.intime)) <= 72
  GROUP BY 
    cs.stay_id
),

cohort_metrics AS (
  SELECT 
    PERCENTILE_CONT(COALESCE(b.procedure_count, 0), 0.75) AS cohort_75th_procedure_burden,
    AVG(cs.los / 24.0) AS cohort_mean_los_days,
    AVG(cs.hospital_expire_flag) AS cohort_hospital_mortality
  FROM cohort_stays cs
  LEFT JOIN procedure_burden b ON cs.stay_id = b.stay_id
),

general_icu AS (
  -- All first ICU stays (general population)
  SELECT 
    los,
    hospital_expire_flag
  FROM (
    SELECT 
      i.stay_id,
      i.los,
      a.hospital_expire_flag,
      ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn_first_stay
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    WHERE 
      i.first_careunit IS NOT NULL
  )
  WHERE rn_first_stay = 1
),

general_metrics AS (
  SELECT 
    AVG(los / 24.0) AS general_mean_los_days,
    AVG(hospital_expire_flag) AS general_hospital_mortality
  FROM general_icu
)

-- Final single-row output
SELECT 
  cm.cohort_75th_procedure_burden,
  cm.cohort_mean_los_days,
  cm.cohort_hospital_mortality,
  gm.general_mean_los_days,
  gm.general_hospital_mortality
FROM cohort_metrics cm
CROSS JOIN general_metrics gm;