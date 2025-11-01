WITH pe_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON diag.subject_id = adm.subject_id
    AND diag.hadm_id = adm.hadm_id
  -- Join to long titles for clarity (optional)
  -- Filtering for Pulmonary Embolism ICD-9 or ICD-10
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '4151%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I26%')
    )
),
first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id, icu.hadm_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN pe_patients pe
    ON pe.subject_id = icu.subject_id
    AND pe.hadm_id = icu.hadm_id
),
first_icu_only AS (
  SELECT *
  FROM first_icu
  WHERE rn = 1
),
proc_counts AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    COUNT(DISTINCT proc.itemid) AS proc_count
  FROM first_icu_only icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON proc.subject_id = icu.subject_id
    AND proc.stay_id = icu.stay_id
    AND proc.starttime >= icu.intime
    AND proc.starttime < TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),
with_los_mort AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.proc_count,
    ROUND(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24, 2) AS hosp_los_days,
    adm.hospital_expire_flag
  FROM proc_counts pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON adm.subject_id = pc.subject_id
    AND adm.hadm_id = pc.hadm_id
),
with_quintile AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS proc_quintile
  FROM with_los_mort
)
SELECT
  proc_quintile,
  ROUND(AVG(proc_count),2) AS avg_proc_count,
  ROUND(AVG(hosp_los_days),2) AS avg_hosp_los_days,
  ROUND(AVG(hospital_expire_flag)*100,1) AS mortality_percent
FROM with_quintile
GROUP BY proc_quintile
ORDER BY proc_quintile;