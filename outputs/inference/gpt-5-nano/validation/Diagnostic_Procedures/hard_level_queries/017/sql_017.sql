WITH
  -- 0) cohort: male patients aged 83-93
  cohort_subjects AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 83 AND 93
  ),

  -- 1) first ICU stay per subject
  first_icu AS (
    SELECT
      s.subject_id,
      s.hadm_id,
      s.stay_id,
      s.intime,
      s.outtime,
      s.los,
      ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  ),

  -- 2) keep only the first ICU stay for each subject and restrict to our cohort
  first_icu_one AS (
    SELECT
      fi.subject_id,
      fi.hadm_id,
      fi.stay_id,
      fi.intime,
      fi.outtime,
      fi.los
    FROM first_icu AS fi
    JOIN cohort_subjects cs ON fi.subject_id = cs.subject_id
    WHERE fi.rn = 1
  ),

  -- 3) identify sepsis on that first ICU stay
  sepsis_first AS (
    SELECT DISTINCT
      fic.subject_id,
      fic.hadm_id,
      fic.stay_id,
      fic.intime,
      fic.los
    FROM first_icu_one AS fic
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON di.subject_id = fic.subject_id
     AND di.hadm_id = fic.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
      ON di.icd_code = dcd.icd_code
     AND di.icd_version = dcd.icd_version
    WHERE LOWER(dcd.long_title) LIKE '%sepsis%'
  ),

  -- 4) count distinct procedures within first 72 hours of ICU intime
  proc_counts AS (
    SELECT
      sf.subject_id,
      sf.hadm_id,
      sf.stay_id,
      sf.intime,
      sf.los,
      COUNT(DISTINCT pe.itemid) AS distinct_proc_count
    FROM sepsis_first sf
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON pe.subject_id = sf.subject_id
     AND pe.hadm_id = sf.hadm_id
     AND pe.stay_id = sf.stay_id
     AND pe.starttime >= sf.intime
     AND pe.starttime <= TIMESTAMP_ADD(sf.intime, INTERVAL 72 HOUR)
    GROUP BY sf.subject_id, sf.hadm_id, sf.stay_id, sf.intime, sf.los
  ),

  -- 5) gather mortality and LOS data for quartile calculation
  mortality_base AS (
    SELECT
      pc.subject_id,
      pc.hadm_id,
      pc.stay_id,
      pc.intime,
      pc.los,
      pc.distinct_proc_count,
      a.hospital_expire_flag,
      a.deathtime
    FROM proc_counts pc
    JOIN sepsis_first sf
      ON pc.subject_id = sf.subject_id
     AND pc.hadm_id = sf.hadm_id
     AND pc.stay_id = sf.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON pc.hadm_id = a.hadm_id
  ),

  -- 6) quartile assignment based on distinct_proc_count
  quartile_assignment AS (
    SELECT
      mb.subject_id,
      mb.hadm_id,
      mb.stay_id,
      mb.intime,
      mb.los,
      mb.distinct_proc_count,
      mb.hospital_expire_flag,
      mb.deathtime,
      NTILE(4) OVER (ORDER BY mb.distinct_proc_count) AS quartile
    FROM mortality_base mb
  )

SELECT
  quartile,
  AVG(distinct_proc_count) AS mean_proc_count,
  AVG(los) AS mean_icu_los_days,
  100.0 * AVG(CASE
                WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1
                ELSE 0
              END) / COUNT(*) AS mortality_percent
FROM quartile_assignment
GROUP BY quartile
ORDER BY quartile;