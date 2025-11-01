WITH pe_hadm AS (
  -- Admissions (hadm_id) with pulmonary embolism diagnoses (ICD-9 or ICD-10 or description match)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE (
    LOWER(d.long_title) LIKE '%pulmonary embol%'                     -- textual match
    OR UPPER(di.icd_code) LIKE 'I26%'                                -- ICD-10 pulmonary embolism
    OR UPPER(di.icd_code) LIKE '415%'                                -- ICD-9 pulmonary embolism codes (e.g., 415.1)
  )
),

first_icustays AS (
  -- Select first ICU stay per subject (earliest intime)
  SELECT *
  FROM (
    SELECT i.*,
           ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  )
  WHERE rn = 1
),

cohort AS (
  -- Join first icustay with patient and admission info, restrict to female 65-75 and PE admissions
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    p.anchor_age,
    a.hospital_expire_flag
  FROM first_icustays f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id
   AND f.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND f.hadm_id IN (SELECT hadm_id FROM pe_hadm)
),

icu_proc_counts AS (
  -- Count procedures_icd entries occurring within 72 hours (3 days) of ICU admission date
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    c.anchor_age,
    c.hospital_expire_flag,
    COUNT(p.icd_code) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON p.subject_id = c.subject_id
   AND p.hadm_id = c.hadm_id
   -- procedures_icd.chartdate is a DATE; compare to DATE(intime) through +3 days (72 hours)
   AND p.chartdate BETWEEN DATE(c.intime) AND DATE_ADD(DATE(c.intime), INTERVAL 3 DAY)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    c.anchor_age,
    c.hospital_expire_flag
),

quartiled AS (
  -- Assign quartiles based on proc_count distribution
  SELECT
    ipc.*,
    NTILE(4) OVER (ORDER BY proc_count) AS proc_count_quartile
  FROM icu_proc_counts ipc
)

-- Final aggregation per quartile: N, mean procedure count, mean ICU LOS (days), hospital mortality (%)
SELECT
  proc_count_quartile AS quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(proc_count), 3) AS mean_procedure_count,
  ROUND(AVG(los), 3) AS mean_icu_los_days,
  ROUND(100.0 * AVG(hospital_expire_flag), 2) AS hospital_mortality_pct
FROM quartiled
GROUP BY proc_count_quartile
ORDER BY proc_count_quartile;