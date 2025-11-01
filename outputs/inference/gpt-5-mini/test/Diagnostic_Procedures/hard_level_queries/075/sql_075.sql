WITH
-- Identify admissions that have a diagnosis mentioning "ketoacidosis" (DKA)
dka_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%ketoacidosis%'
),

-- First ICU stay per subject (by intime)
first_icustays AS (
  SELECT *
  FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

-- Cohort: first ICU stays for male patients aged 39-49 with a DKA diagnosis on the hospital admission
cohort_stays AS (
  SELECT f.*,
         p.gender,
         p.anchor_age,
         a.hospital_expire_flag,
         a.admittime
  FROM first_icustays f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.hadm_id = a.hadm_id
  JOIN dka_hadm d
    ON f.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

-- Count distinct procedure itemids in the first 24 hours of each first ICU stay
proc_counts AS (
  SELECT cs.stay_id,
         COUNT(DISTINCT pe.itemid) AS proc_count
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = cs.stay_id
   AND pe.starttime IS NOT NULL
   AND pe.starttime >= cs.intime
   AND pe.starttime < TIMESTAMP_ADD(cs.intime, INTERVAL 24 HOUR)
  GROUP BY cs.stay_id
),

-- Combine cohort stays with procedure counts (missing -> 0)
cohort_with_counts AS (
  SELECT cs.subject_id,
         cs.hadm_id,
         cs.stay_id,
         COALESCE(pc.proc_count, 0) AS proc_count,
         cs.los,
         cs.hospital_expire_flag
  FROM cohort_stays cs
  LEFT JOIN proc_counts pc
    ON cs.stay_id = pc.stay_id
),

-- Assign quintiles based on proc_count
cohort_with_quintile AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM cohort_with_counts
)

-- Aggregate statistics by quintile
SELECT
  quintile,
  COUNT(*) AS num_stays,
  ROUND(AVG(proc_count), 2) AS mean_proc_count,
  MIN(proc_count) AS min_proc_count,
  MAX(proc_count) AS max_proc_count,
  ROUND(AVG(los), 3) AS mean_icu_los_days,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS hospital_mortality_pct
FROM cohort_with_quintile
GROUP BY quintile
ORDER BY quintile;