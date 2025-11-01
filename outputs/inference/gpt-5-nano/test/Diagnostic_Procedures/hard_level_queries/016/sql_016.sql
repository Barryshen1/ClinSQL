WITH
  -- 1) First ICU stay per patient within the male 88-98 age band
  base_first_icu AS (
    SELECT i.subject_id,
           i.hadm_id,
           i.stay_id,
           i.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON p.subject_id = i.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 88 AND 98
  ),
  first_icu AS (
    SELECT subject_id, hadm_id, stay_id, intime
    FROM (
      SELECT fi.*,
             ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
      FROM base_first_icu fi
    ) t
    WHERE rn = 1
  ),

  -- 2) Eligible: first ICU stay's admission has pneumonia
  eligible AS (
    SELECT f.subject_id, f.hadm_id, f.stay_id, f.intime
    FROM first_icu f
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON d.subject_id = f.subject_id AND d.hadm_id = f.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE REGEXP_CONTAINS(LOWER(di.long_title), r'pneumonia')
  ),

  -- 3) Diagnostic procedure counts within 72 hours of ICU intime
  diag_counts AS (
    SELECT e.subject_id,
           e.hadm_id,
           e.stay_id,
           e.intime,
           SUM(CASE WHEN di.itemid IS NOT NULL
                    AND (REGEXP_CONTAINS(LOWER(di.category), r'diagnostic')
                         OR REGEXP_CONTAINS(LOWER(di.label), r'diagnostic'))
                     THEN 1 ELSE 0 END) AS diag_proc_count,
           i.los AS icu_los_hours,
           a.hospital_expire_flag,
           a.deathtime
    FROM eligible e
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON pe.stay_id = e.stay_id
     AND pe.starttime >= e.intime
     AND pe.starttime < TIMESTAMP_ADD(e.intime, INTERVAL 72 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON di.itemid = pe.itemid
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON i.stay_id = e.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON a.hadm_id = e.hadm_id
    GROUP BY e.subject_id, e.hadm_id, e.stay_id, e.intime, i.los, a.hospital_expire_flag, a.deathtime
  ),

  -- 4) Prepare data with quintile computation
  counts_with_quintile AS (
    SELECT NTILE(5) OVER (ORDER BY diag_proc_count) AS quintile,
           diag_proc_count,
           icu_los_hours,
           hospital_expire_flag,
           deathtime
    FROM diag_counts
  )

SELECT
  quintile,
  AVG(diag_proc_count) AS avg_diag_proc_count,
  AVG(icu_los_hours / 24.0) AS avg_icu_los_days,
  100.0 * AVG(CASE
                WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1.0
                ELSE 0.0
              END) AS mortality_percent
FROM counts_with_quintile
GROUP BY quintile
ORDER BY quintile;