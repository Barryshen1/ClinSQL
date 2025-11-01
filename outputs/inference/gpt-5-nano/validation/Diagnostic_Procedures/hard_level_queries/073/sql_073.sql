WITH
  -- 1) first ICU stay per patient
  first_icustay AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los
    FROM (
      SELECT *,
             ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) AS icu
    WHERE rn = 1
  ),

  -- 2) hepatic failure during that first ICU stay
  hepatic_failure AS (
    SELECT fi.subject_id, fi.hadm_id
    FROM first_icustay fi
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON diag.subject_id = fi.subject_id AND diag.hadm_id = fi.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
      ON diag.icd_code = dcd.icd_code AND diag.icd_version = dcd.icd_version
    WHERE UPPER(dcd.long_title) LIKE '%HEPATIC FAILURE%'
    GROUP BY fi.subject_id, fi.hadm_id
  ),

  -- 3) base cohort: male, age 90-100, first ICU stay, hepatic failure present
  cohort_base AS (
    SELECT
      fi.subject_id,
      fi.hadm_id,
      fi.stay_id,
      fi.intime,
      fi.los AS icu_los_hours,
      (fi.los / 24.0) AS icu_los_days,
      CAST(a.hospital_expire_flag AS INT64) AS died_in_hospital
    FROM first_icustay fi
    JOIN hepatic_failure hf
      ON fi.subject_id = hf.subject_id AND fi.hadm_id = hf.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON fi.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON fi.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
      AND pat.anchor_age BETWEEN 90 AND 100
  ),

  -- 4) count distinct diagnostic procedures within first 72 hours of ICU start
  proc_counts AS (
    SELECT
      cb.subject_id,
      cb.hadm_id,
      COUNT(DISTINCT pe.itemid) AS num_diag_procs
    FROM cohort_base cb
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
         ON pe.subject_id = cb.subject_id
        AND pe.hadm_id = cb.hadm_id
        AND pe.stay_id = cb.stay_id
        AND pe.starttime >= cb.intime
        AND pe.starttime < TIMESTAMP_ADD(cb.intime, INTERVAL 72 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
         ON pe.itemid = di.itemid
    WHERE di.itemid IS NOT NULL
      AND (
            LOWER(di.label) LIKE '%diagnostic%'
            OR LOWER(di.label) LIKE '%imaging%'
            OR LOWER(di.label) LIKE '%diagnose%'
          )
    GROUP BY cb.subject_id, cb.hadm_id
  )

SELECT
  quartile,
  COUNT(*) AS num_patients,
  MIN(num_diag_procs) AS min_procs,
  MAX(num_diag_procs) AS max_procs,
  AVG(num_diag_procs) AS mean_procs,
  AVG(icu_los_days) AS mean_los_days,
  100.0 * AVG(died_in_hospital) AS in_hospital_mortality_pct
FROM (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.icu_los_days,
    c.died_in_hospital,
    COALESCE(pc.num_diag_procs, 0) AS num_diag_procs,
    NTILE(4) OVER (ORDER BY COALESCE(pc.num_diag_procs, 0)) AS quartile
  FROM cohort_base c
  LEFT JOIN proc_counts pc
    ON c.subject_id = pc.subject_id AND c.hadm_id = pc.hadm_id
) AS sub
GROUP BY quartile
ORDER BY quartile;