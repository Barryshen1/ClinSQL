WITH first_icu AS (
  -- take each subject's first ICU stay
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
),

pneumonia_first_icu AS (
  -- filter to first ICU stays for males aged 88-98 whose admission has a pneumonia diagnosis
  SELECT fi.*
  FROM first_icu fi
  WHERE fi.rn = 1
    AND fi.gender = 'M'
    AND fi.anchor_age BETWEEN 88 AND 98
    AND fi.hadm_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code
       AND diag.icd_version = d.icd_version
      WHERE diag.hadm_id = fi.hadm_id
        AND LOWER(d.long_title) LIKE '%pneumonia%'
    )
),

proc_counts AS (
  -- count procedureevents within first 72 hours of ICU admission for each selected stay
  SELECT
    pf.subject_id,
    pf.hadm_id,
    pf.stay_id,
    pf.intime,
    pf.outtime,
    pf.los,
    pf.anchor_age,
    pf.gender,
    a.hospital_expire_flag,
    COUNT(pe.starttime) AS proc_count
  FROM pneumonia_first_icu pf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = pf.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = pf.subject_id
   AND pe.hadm_id = pf.hadm_id
   AND pe.stay_id = pf.stay_id
   AND pe.starttime >= pf.intime
   AND pe.starttime < TIMESTAMP_ADD(pf.intime, INTERVAL 72 HOUR)
  GROUP BY
    pf.subject_id,
    pf.hadm_id,
    pf.stay_id,
    pf.intime,
    pf.outtime,
    pf.los,
    pf.anchor_age,
    pf.gender,
    a.hospital_expire_flag
),

ranked AS (
  -- assign quintiles based on proc_count distribution
  SELECT
    pc.*,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts pc
)

-- aggregate outcomes per quintile
SELECT
  quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(proc_count), 2) AS avg_procedure_count,
  ROUND(AVG(los), 2) AS avg_icu_los_days,
  ROUND(100.0 * SUM(IF(hospital_expire_flag = 1, 1, 0)) / COUNT(*), 2) AS in_hospital_mortality_pct
FROM ranked
GROUP BY quintile
ORDER BY quintile;