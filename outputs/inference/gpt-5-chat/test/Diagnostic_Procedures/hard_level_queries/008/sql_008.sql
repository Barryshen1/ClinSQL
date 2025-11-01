WITH ugib_hadm AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE REGEXP_CONTAINS(LOWER(dd.long_title),
    r'hematemesis|melena|upper gastrointestinal hemorrhage|upper gi hemorrhage|gi bleed|gastrointestinal bleed')
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN ugib_hadm uh
    ON icu.subject_id = uh.subject_id AND icu.hadm_id = uh.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
),
proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(pe.itemid) AS diag_procs_24h,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND LOWER(pe.ordercategorydescription) LIKE '%diagnostic%'
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
quintiled AS (
  SELECT
    pc.*,
    NTILE(5) OVER (ORDER BY diag_procs_24h) AS quintile,
    TIMESTAMP_DIFF(pc.dischtime, pc.admittime, HOUR)/24.0 AS hosp_los_days
  FROM proc_counts pc
)
SELECT
  quintile,
  ROUND(AVG(diag_procs_24h),2) AS avg_diag_procs_24h,
  ROUND(AVG(hosp_los_days),2)   AS avg_hosp_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_hosp_mortality_pct,
  COUNT(*) AS n_stays
FROM quintiled
GROUP BY quintile
ORDER BY quintile;