WITH first_icu AS (
  -- each subject's first ICU stay
  SELECT *
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
),

hepatic_admissions AS (
  -- admissions with a hepatic failure diagnosis (ICD K72* or text match)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE
    -- ICD code family for liver/hepatic failure
    LOWER(di.icd_code) LIKE 'k72%' 
    OR
    (
      LOWER(COALESCE(dd.long_title, '')) LIKE '%hepatic%' 
      AND LOWER(COALESCE(dd.long_title, '')) LIKE '%failure%'
    )
    OR LOWER(COALESCE(dd.long_title, '')) LIKE '%liver failure%'
),

proc_counts AS (
  -- count distinct procedure codes within first 72 hours of the ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    COUNT(DISTINCT p.icd_code) AS proc_count
  FROM first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON p.hadm_id = f.hadm_id
   AND DATE(p.chartdate) BETWEEN DATE(f.intime)
                            AND DATE(TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR))
  GROUP BY f.subject_id, f.hadm_id
),

cohort AS (
  -- assemble cohort: male, age 90-100, hepatic failure on the admission, with first ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    a.hospital_expire_flag
  FROM first_icu f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = f.hadm_id
   AND a.subject_id = f.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = f.subject_id
  -- filter demographics
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    -- require hepatic failure diagnosis on that admission
    AND EXISTS (
      SELECT 1
      FROM hepatic_admissions h
      WHERE h.hadm_id = f.hadm_id
    )
)

-- final step: attach procedure counts, compute quartiles, aggregate per quartile
SELECT
  quartile,
  COUNT(*) AS n_patients,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures,
  ROUND(AVG(proc_count), 2) AS mean_procedures,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*), 2) AS inhospital_mortality_pct
FROM (
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(pc.proc_count, 0) AS proc_count,
    c.los,
    c.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY COALESCE(pc.proc_count, 0)) AS quartile
  FROM cohort c
  LEFT JOIN proc_counts pc
    ON pc.hadm_id = c.hadm_id
   AND pc.subject_id = c.subject_id
)
GROUP BY quartile
ORDER BY quartile;