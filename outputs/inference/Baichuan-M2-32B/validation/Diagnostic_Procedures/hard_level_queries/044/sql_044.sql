WITH patient_icu AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.subject_id,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    TIMESTAMP_DIFF(
      i.intime,
      DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
      INTERVAL p.anchor_age YEAR),
      YEAR
    ) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
cardiogenic_shock_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%cardiogenic shock%'
),
icu_stays_with_diagnosis AS (
  SELECT 
    p.*
  FROM patient_icu p
  INNER JOIN cardiogenic_shock_admissions c
    ON p.hadm_id = c.hadm_id
  WHERE p.age_at_icu BETWEEN 82 AND 92
),
procedure_counts AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    COUNT(*) AS procedure_count  -- Fixed: Count all events (no unique ID exists)
  FROM icu_stays_with_diagnosis i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.stay_id, i.hadm_id
),
hospital_admission_details AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS hospital_los_days,
    hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE dischtime IS NOT NULL
),
combined AS (
  SELECT 
    pc.stay_id,
    pc.procedure_count,
    had.hospital_los_days,
    had.hospital_expire_flag
  FROM procedure_counts pc
  INNER JOIN hospital_admission_details had
    ON pc.hadm_id = had.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM combined
)
SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_percentage
FROM quintiles
GROUP BY quintile
ORDER BY quintile;