WITH stays AS (
  -- Per-ICU-stay info, plus age at ICU admission and a sepsis indicator for the admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los_days,
    adm.hospital_expire_flag,
    LOWER(pat.gender) AS gender,
    (pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year)) AS age_at_intime,
    MAX(
      CASE
        WHEN did.long_title LIKE '%sepsis%' OR
             did.long_title LIKE '%septicaemia%' OR
             did.long_title LIKE '%septicemia%'
        THEN 1 ELSE 0
      END
    ) AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON icu.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON di.icd_code = did.icd_code
   AND di.icd_version = did.icd_version
  GROUP BY
    icu.subject_id, icu.hadm_id, icu.stay_id,
    icu.intime, icu.outtime, adm.hospital_expire_flag,
    pat.gender, pat.anchor_age, pat.anchor_year, icu.los
),
procs AS (
  -- Count procedures within the first 24 hours after ICU intime for each stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.icu_los_days,
    s.hospital_expire_flag,
    s.gender,
    s.age_at_intime,
    s.has_sepsis,
    COUNT(pe.stay_id) AS proc_first24h
  FROM stays AS s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.stay_id = s.stay_id
   AND pe.starttime >= s.intime
   AND pe.starttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime,
    s.icu_los_days, s.hospital_expire_flag, s.gender,
    s.age_at_intime, s.has_sepsis
)
SELECT
  cohort_label,
  p75_proc_first24h,
  p90_proc_first24h,
  avg_icu_los_days,
  in_hospital_mortality_rate
FROM (
  SELECT
     CASE WHEN has_sepsis = 1 THEN 'Sepsis_53-63' ELSE 'NonSepsis_53-63' END AS cohort_label,
     APPROX_QUANTILES(proc_first24h, 4)[OFFSET(3)] AS p75_proc_first24h,
     APPROX_QUANTILES(proc_first24h, 10)[OFFSET(9)] AS p90_proc_first24h,
     AVG(icu_los_days) AS avg_icu_los_days,
     AVG(hospital_expire_flag) AS in_hospital_mortality_rate
  FROM procs
  WHERE age_at_intime BETWEEN 53 AND 63
  GROUP BY CASE WHEN has_sepsis = 1 THEN 'Sepsis_53-63' ELSE 'NonSepsis_53-63' END
) AS x
ORDER BY cohort_label;