WITH 
  -- Filter patients and admissions
  eligible_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      i.stay_id,
      a.admittime,
      TIMESTAMP_DIFF(a.admittime, p.anchor_year, DAY) AS age,
      p.gender,
      CASE 
        WHEN d.icd_code IN (
          SELECT icd_code 
          FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE long_title LIKE '%Hepatic Failure%'
        ) THEN 1 
        ELSE 0 
      END AS has_hepatic_failure
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
    WHERE 
      p.gender = 'M' 
      AND TIMESTAMP_DIFF(a.admittime, p.anchor_year, DAY) BETWEEN 32850 AND 36500
  ),

  -- Identify procedures and diagnoses within the first 72 hours of ICU stay
  procedures_within_72hrs AS (
    SELECT 
      e.subject_id, 
      e.hadm_id, 
      e.stay_id,
      p.icd_code,
      p.chartdate,
      TIMESTAMP_DIFF(p.chartdate, i.intime, HOUR) AS hours_since_icu_admit
    FROM 
      eligible_patients e
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
      ON e.hadm_id = p.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON e.hadm_id = i.hadm_id AND e.stay_id = i.stay_id
    WHERE 
      has_hepatic_failure = 1 
      AND hours_since_icu_admit <= 72
  ),

  -- Count distinct procedures per patient
  patient_procedure_counts AS (
    SELECT 
      subject_id, 
      hadm_id, 
      COUNT(DISTINCT icd_code) AS procedure_count
    FROM 
      procedures_within_72hrs
    GROUP BY 
      subject_id, 
      hadm_id
  ),

  -- Calculate quartiles of procedure counts
  quartile_cuts AS (
    SELECT 
      APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS q1,
      APPROX_QUANTILES(procedure_count, 4)[OFFSET(2)] AS q2,
      APPROX_QUANTILES(procedure_count, 4)[OFFSET(3)] AS q3
    FROM 
      patient_procedure_counts
  ),

  -- Assign patients to quartiles
  patient_quartiles AS (
    SELECT 
      subject_id, 
      hadm_id, 
      procedure_count,
      CASE 
        WHEN procedure_count < (SELECT q1 FROM quartile_cuts) THEN 1
        WHEN procedure_count < (SELECT q2 FROM quartile_cuts) THEN 2
        WHEN procedure_count < (SELECT q3 FROM quartile_cuts) THEN 3
        ELSE 4 
      END AS quartile
    FROM 
      patient_procedure_counts
  ),

  -- Calculate LOS and mortality
  patient_outcomes AS (
    SELECT 
      p.subject_id, 
      p.hadm_id, 
      a.dischtime,
      a.hospital_expire_flag,
      TIMESTAMP_DIFF(a.dischtime, i.intime, DAY) AS los_days
    FROM 
      eligible_patients p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.hadm_id = a.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON p.hadm_id = i.hadm_id AND p.stay_id = i.stay_id
  )

-- Final aggregation
SELECT 
  pq.quartile,
  COUNT(DISTINCT pq.subject_id) AS num_patients,
  MIN(pq.procedure_count) AS min_procedures,
  MAX(pq.procedure_count) AS max_procedures,
  AVG(pq.procedure_count) AS mean_procedures,
  AVG(po.los_days) AS mean_los_days,
  AVG(CASE WHEN po.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS in_hospital_mortality_pct
FROM 
  patient_quartiles pq
JOIN 
  patient_outcomes po 
  ON pq.subject_id = po.subject_id AND pq.hadm_id = po.hadm_id
GROUP BY 
  pq.quartile
ORDER BY 
  pq.quartile;