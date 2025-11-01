WITH sepsis_hadms AS (
  -- admissions with any diagnosis whose description contains "sepsis"
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
   AND d.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%sepsis%'
),

icu_sepsis_stays AS (
  -- ICU stays for admissions flagged with sepsis and patients aged 53-63 (anchor_age)
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE icu.hadm_id IN (SELECT hadm_id FROM sepsis_hadms)
    AND p.anchor_age BETWEEN 53 AND 63
),

proc_counts_per_stay AS (
  -- Count procedureevents occurring within first 24 hours of ICU intime.
  -- Use LEFT JOIN so stays without procedures get proc_count = 0.
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.gender,
    s.anchor_age,
    s.los,
    s.hospital_expire_flag,
    COUNT(pe.starttime) AS proc_count_first_24h
  FROM icu_sepsis_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = s.stay_id
   AND pe.starttime IS NOT NULL
   AND pe.starttime >= s.intime
   AND pe.starttime <= TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id, s.gender, s.anchor_age, s.los, s.hospital_expire_flag
),

aggregated AS (
  -- Prepare cohort-level aggregates: female vs all (age-matched)
  SELECT
    'Female (53-63, sepsis)' AS cohort,
    COUNT(*) AS n_stays,
    -- 75th and 90th percentiles via APPROX_QUANTILES (100 buckets -> offsets 75 and 90)
    APPROX_QUANTILES(proc_count_first_24h, 100)[OFFSET(75)] AS proc_count_p75,
    APPROX_QUANTILES(proc_count_first_24h, 100)[OFFSET(90)] AS proc_count_p90,
    AVG(los) AS avg_icu_los_hours,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM proc_counts_per_stay
  WHERE gender = 'F'

  UNION ALL

  SELECT
    'All sexes (53-63, sepsis)' AS cohort,
    COUNT(*) AS n_stays,
    APPROX_QUANTILES(proc_count_first_24h, 100)[OFFSET(75)] AS proc_count_p75,
    APPROX_QUANTILES(proc_count_first_24h, 100)[OFFSET(90)] AS proc_count_p90,
    AVG(los) AS avg_icu_los_hours,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM proc_counts_per_stay
)

SELECT *
FROM aggregated
ORDER BY cohort;