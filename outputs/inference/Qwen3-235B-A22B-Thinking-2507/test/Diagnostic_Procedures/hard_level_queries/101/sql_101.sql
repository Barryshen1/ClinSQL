WITH all_stays AS (
  SELECT
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    -- Flag COPD exacerbation diagnosis (J440/J441 in ICD-10)
    MAX(CASE WHEN d.icd_code IN ('J440', 'J441') AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_copd_exac
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Compute age at admission
  LEFT JOIN UNNEST([STRUCT(
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  )]) age_calc
  -- Join diagnoses for COPD flag
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND age_calc.age BETWEEN 88 AND 98  -- Age 88-98 inclusive
  GROUP BY i.stay_id, i.intime, i.los, a.hospital_expire_flag
),
index_procedure_counts AS (
  SELECT
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  INNER JOIN all_stays s
    ON p.stay_id = s.stay_id
  WHERE s.has_copd_exac = 1
    AND p.starttime <= TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)  -- Fixed: charttime -> starttime
  GROUP BY p.stay_id
),
index_los_mortality AS (
  SELECT los, hospital_expire_flag
  FROM all_stays
  WHERE has_copd_exac = 1
),
comparison_los_mortality AS (
  SELECT los, hospital_expire_flag
  FROM all_stays
  WHERE has_copd_exac = 0
),
index_proc_75th AS (
  SELECT PERCENTILE_CONT(proc_count, 0.75) OVER () AS proc_75th
  FROM index_procedure_counts
  LIMIT 1
)
SELECT
  'index' AS cohort,
  (SELECT proc_75th FROM index_proc_75th) AS proc_75th,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) AS mortality
FROM index_los_mortality
UNION ALL
SELECT
  'comparison' AS cohort,
  NULL AS proc_75th,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) AS mortality
FROM comparison_los_mortality;