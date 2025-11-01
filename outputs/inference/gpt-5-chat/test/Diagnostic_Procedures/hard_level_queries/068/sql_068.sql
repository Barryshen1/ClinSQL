WITH cohort AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    ie.intime as icu_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.subject_id = adm.subject_id
   AND ie.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  -- Filter: male, age range
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    -- Asthma ICD-9 or ICD-10
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '493%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'J45%')
    )
),
proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(pe.itemid) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.subject_id = pe.subject_id
   AND c.hadm_id = pe.hadm_id
   AND c.stay_id = pe.stay_id
   AND pe.starttime >= c.icu_intime
   AND pe.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
),
with_quartiles AS (
  SELECT
    pc.*,
    -- Convert LOS to fractional days
    TIMESTAMP_DIFF(pc.dischtime, pc.admittime, HOUR)/24.0 AS los_days,
    NTILE(4) OVER (ORDER BY proc_count) AS proc_quartile
  FROM proc_counts pc
)
SELECT
  proc_quartile,
  AVG(proc_count) AS mean_proc_count,
  AVG(los_days)  AS mean_hosp_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM with_quartiles
GROUP BY proc_quartile
ORDER BY proc_quartile;