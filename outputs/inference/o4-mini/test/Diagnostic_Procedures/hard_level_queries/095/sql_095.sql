WITH icu_data AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR) AS first24_end,
    icu.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.subject_id = a.subject_id
   AND icu.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
),
pe_admissions AS (
  -- Identify admissions with pulmonary embolism
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pulmonary embolism%'
),
diag_counts AS (
  -- Count lab events in first 24h per ICU stay
  SELECT
    icu.stay_id,
    COUNT(l.labevent_id) AS diagnostic_count,
    icu.los,
    icu.hospital_expire_flag,
    CASE 
      WHEN pe.subject_id IS NOT NULL THEN 'pe'
      ELSE 'all'
    END AS cohort
  FROM icu_data icu
  LEFT JOIN pe_admissions pe
    ON icu.subject_id = pe.subject_id
   AND icu.hadm_id = pe.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON icu.subject_id = l.subject_id
   AND icu.hadm_id = l.hadm_id
   AND l.charttime BETWEEN icu.intime AND icu.first24_end
  GROUP BY
    icu.stay_id,
    icu.los,
    icu.hospital_expire_flag,
    CASE 
      WHEN pe.subject_id IS NOT NULL THEN 'pe'
      ELSE 'all'
    END
),
stats AS (
  -- Compute the 75th percentile, average LOS, and mortality rate by cohort
  SELECT
    cohort,
    APPROX_QUANTILES(diagnostic_count, 100)[OFFSET(75)] AS pct75_diagnostic_score,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM diag_counts
  GROUP BY cohort
)
SELECT
  cohort,
  pct75_diagnostic_score,
  avg_los,
  mortality_rate
FROM stats;