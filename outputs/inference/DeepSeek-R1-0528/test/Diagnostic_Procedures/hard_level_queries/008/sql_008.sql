WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    ie.stay_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ie.intime,
    ie.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON a.hadm_id = ie.hadm_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE a.hadm_id = diag.hadm_id
        AND diag.icd_code IN ('5780', '5781', '5789', 'K920', 'K921', 'K922')
    )
),
-- Filter age 48-58
cohort_filtered AS (
  SELECT *
  FROM cohort
  WHERE age_adm BETWEEN 48 AND 58
),
-- Count procedures in first 24h of ICU stay
procedure_counts AS (
  SELECT 
    c.stay_id,
    COUNT(pe.itemid) AS num_procedures
  FROM cohort_filtered c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),
-- Combine with admission outcomes
stay_data AS (
  SELECT 
    c.*,
    COALESCE(pc.num_procedures, 0) AS num_procedures,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_hospital
  FROM cohort_filtered c
  LEFT JOIN procedure_counts pc
    ON c.stay_id = pc.stay_id
),
-- Assign quintiles
with_quintile AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY num_procedures) AS quintile
  FROM stay_data
)
-- Aggregate results by quintile
SELECT 
  quintile,
  AVG(num_procedures) AS avg_procedures,
  AVG(los_hospital) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
FROM with_quintile
GROUP BY quintile
ORDER BY quintile;