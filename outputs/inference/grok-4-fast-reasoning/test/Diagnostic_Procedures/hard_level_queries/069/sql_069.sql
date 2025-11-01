WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 44 AND 54
),
first_icu_stays AS (
  SELECT i.subject_id, i.stay_id, i.hadm_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients ep ON i.subject_id = ep.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) = 1
),
pe_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = '10' AND icd_code LIKE 'I26%')
     OR (icd_version = '9' AND icd_code LIKE '415.1%')
),
first_pe_icu AS (
  SELECT f.subject_id, f.stay_id, f.hadm_id, f.intime
  FROM first_icu_stays f
  INNER JOIN pe_hadms ph ON f.hadm_id = ph.hadm_id
),
procedure_counts AS (
  SELECT 
    f.subject_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM first_pe_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON pe.stay_id = f.stay_id
    AND pe.starttime >= f.intime
    AND pe.starttime < TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY f.subject_id
),
hospital_info AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los,
    CAST(a.hospital_expire_flag AS INT64) AS mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN first_pe_icu f ON a.hadm_id = f.hadm_id
),
patient_data AS (
  SELECT 
    pc.subject_id,
    COALESCE(pc.proc_count, 0) AS proc_count,
    hi.hospital_los,
    hi.mortality
  FROM procedure_counts pc
  INNER JOIN hospital_info hi ON pc.subject_id = hi.subject_id
)
SELECT 
  quintile,
  ROUND(AVG(proc_count), 2) AS avg_proc_count,
  ROUND(AVG(hospital_los), 2) AS avg_hospital_los,
  ROUND(AVG(mortality) * 100, 2) AS mortality_pct
FROM (
  SELECT 
    proc_count,
    hospital_los,
    mortality,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM patient_data
)
GROUP BY quintile
ORDER BY quintile;