WITH
-- identify hospital admissions with ARDS (ICD descriptions containing ARDS / acute respiratory distress)
ards_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%acute respiratory distress%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%ards%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%respiratory distress%'
),
-- per-ICU-stay summary: procedures in first 24h (distinct itemid), hospital LOS (days), hospital_expire_flag
icustay_summary AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    -- fractional hospital LOS in days; NULL if dischtime is NULL
    CASE
      WHEN a.dischtime IS NOT NULL THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0
      ELSE NULL
    END AS hosp_los_days,
    -- count distinct procedure itemid in first 24 hours of the ICU stay
    COUNT(DISTINCT pe.itemid) AS procedures_24h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON s.subject_id = pe.subject_id
   AND s.hadm_id = pe.hadm_id
   AND pe.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id, p.gender, p.anchor_age, a.hospital_expire_flag,
    CASE WHEN a.dischtime IS NOT NULL THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 ELSE NULL END
)

-- final aggregation: compute percentiles and averages for the two cohorts
SELECT
  cohort,
  procedures_p25,
  procedures_p75,
  procedures_p95,
  avg_hosp_los_days,
  hospital_mortality_rate,
  n_icustays
FROM (
  -- ARDS female 84-94 cohort
  SELECT
    'ARDS_female_84_94' AS cohort,
    -- APPROX_QUANTILES(...,100) returns 101 values: offsets correspond to percentiles
    (APPROX_QUANTILES(procedures_24h, 100))[OFFSET(25)] AS procedures_p25,
    (APPROX_QUANTILES(procedures_24h, 100))[OFFSET(75)] AS procedures_p75,
    (APPROX_QUANTILES(procedures_24h, 100))[OFFSET(95)] AS procedures_p95,
    AVG(hosp_los_days) AS avg_hosp_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate,
    COUNT(*) AS n_icustays
  FROM icustay_summary s
  JOIN ards_hadm a ON s.hadm_id = a.hadm_id
  WHERE s.gender = 'F'
    AND s.anchor_age BETWEEN 84 AND 94

  UNION ALL

  -- General ICU population (all icustays with admissions/patient info)
  SELECT
    'General_ICU' AS cohort,
    (APPROX_QUANTILES(procedures_24h, 100))[OFFSET(25)] AS procedures_p25,
    (APPROX_QUANTILES(procedures_24h, 100))[OFFSET(75)] AS procedures_p75,
    (APPROX_QUANTILES(procedures_24h, 100))[OFFSET(95)] AS procedures_p95,
    AVG(hosp_los_days) AS avg_hosp_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate,
    COUNT(*) AS n_icustays
  FROM icustay_summary
)
ORDER BY cohort;