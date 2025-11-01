WITH ugib_hadm AS (
  -- admissions with diagnoses whose description suggests upper GI bleeding
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%upper gastrointestinal%'
     OR LOWER(dd.long_title) LIKE '%hematemesis%'
     OR LOWER(dd.long_title) LIKE '%melena%'
     OR LOWER(dd.long_title) LIKE '%gastrointestinal bleeding%'
     OR LOWER(dd.long_title) LIKE '%gi hemorrhage%'
),

cohort_admissions AS (
  -- admissions for male patients age 74-84 that have a UGIB diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN ugib_hadm u
    ON a.hadm_id = u.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),

first_icustay AS (
  -- for each admission in the cohort, take the first ICU stay (earliest intime) for that hadm_id
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN cohort_admissions ca
    ON s.hadm_id = ca.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) = 1
),

proc_counts AS (
  -- count procedureevents in the first 72 hours of the ICU stay; include stays with zero events
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    ca.anchor_age,
    ca.gender,
    COALESCE(COUNT(pe.starttime), 0) AS procedure_count,
    -- hospital LOS in days (fractional)
    TIMESTAMP_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0 AS hosp_los_days
  FROM first_icustay f
  JOIN cohort_admissions ca
    ON f.hadm_id = ca.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = f.stay_id
   AND pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id, f.intime,
    ca.admittime, ca.dischtime, ca.hospital_expire_flag, ca.anchor_age, ca.gender
),

with_quartile AS (
  -- assign quartiles of diagnostic intensity (procedure_count) across the cohort
  SELECT
    pc.*,
    NTILE(4) OVER (ORDER BY procedure_count) AS intensity_quartile
  FROM proc_counts pc
)

-- Final aggregation per quartile: mean procedure count, mean hospital LOS (days), and in-hospital mortality
SELECT
  intensity_quartile AS quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(hosp_los_days), 2) AS mean_hospital_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 3) AS in_hospital_mortality_proportion
FROM with_quartile
GROUP BY intensity_quartile
ORDER BY intensity_quartile;