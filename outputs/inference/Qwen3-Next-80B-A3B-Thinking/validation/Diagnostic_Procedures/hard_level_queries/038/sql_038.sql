WITH patients_filtered AS (
  SELECT subject_id, anchor_age, gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 60 AND 70
),
first_icu_stays AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime, 
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_filtered p ON i.subject_id = p.subject_id
),
first_icu_stays_rn1 AS (
  SELECT *
  FROM first_icu_stays
  WHERE rn = 1
),
ich_diagnosis AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id, f.intime, f.los
  FROM first_icu_stays_rn1 f
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = f.hadm_id
      AND d.icd_version = 10
      AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
  )
),
procedure_counts AS (
  SELECT 
    i.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM ich_diagnosis i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL 72 HOUR
  GROUP BY i.stay_id
),
specific_cohort AS (
  SELECT 
    pc.procedure_count,
    i.los,
    a.hospital_expire_flag
  FROM ich_diagnosis i
  LEFT JOIN procedure_counts pc ON i.stay_id = pc.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
general_population AS (
  SELECT 
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)
SELECT
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS proc_75th,
  AVG(los) AS mean_los_specific,
  AVG(hospital_expire_flag) AS mortality_specific,
  (SELECT AVG(los) FROM general_population) AS mean_los_general,
  (SELECT AVG(hospital_expire_flag) FROM general_population) AS mortality_general
FROM specific_cohort;