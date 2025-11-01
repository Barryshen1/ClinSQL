WITH hf_cohort AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 70 AND 80
    AND (
      dx.icd_code LIKE '428%' OR dx.icd_code LIKE 'I50%'
    )
),
diagnostic_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.los,
    c.hospital_expire_flag,
    COUNT(DISTINCT lab.labevent_id) AS lab_count,
    COUNT(DISTINCT micro.microevent_id) AS micro_count,
    COUNT(DISTINCT lab.labevent_id) + COUNT(DISTINCT micro.microevent_id) AS total_diag_count
  FROM hf_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON c.subject_id = lab.subject_id
    AND c.hadm_id = lab.hadm_id
    AND lab.charttime >= c.intime
    AND lab.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON c.subject_id = micro.subject_id
    AND c.hadm_id = micro.hadm_id
    AND micro.charttime >= c.intime
    AND micro.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.intime, c.los, c.hospital_expire_flag
),
general_cohort AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.los, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
),
general_counts AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.stay_id,
    g.intime,
    g.los,
    g.hospital_expire_flag,
    COUNT(DISTINCT lab.labevent_id) AS lab_count,
    COUNT(DISTINCT micro.microevent_id) AS micro_count,
    COUNT(DISTINCT lab.labevent_id) + COUNT(DISTINCT micro.microevent_id) AS total_diag_count
  FROM general_cohort g
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON g.subject_id = lab.subject_id
    AND g.hadm_id = lab.hadm_id
    AND lab.charttime >= g.intime
    AND lab.charttime < TIMESTAMP_ADD(g.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON g.subject_id = micro.subject_id
    AND g.hadm_id = micro.hadm_id
    AND micro.charttime >= g.intime
    AND micro.charttime < TIMESTAMP_ADD(g.intime, INTERVAL 72 HOUR)
  GROUP BY g.subject_id, g.hadm_id, g.stay_id, g.intime, g.los, g.hospital_expire_flag
)
SELECT
  'HF Cohort' AS cohort,
  AVG(total_diag_count) AS mean_diag_intensity,
  APPROX_QUANTILES(total_diag_count, 100)[OFFSET(50)] AS median_diag_intensity,
  APPROX_QUANTILES(total_diag_count, 100)[OFFSET(75)] AS p75_diag_intensity,
  APPROX_QUANTILES(total_diag_count, 100)[OFFSET(95)] AS p95_diag_intensity,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM diagnostic_counts
UNION ALL
SELECT
  'General ICU' AS cohort,
  AVG(total_diag_count) AS mean_diag_intensity,
  APPROX_QUANTILES(total_diag_count, 100)[OFFSET(50)] AS median_diag_intensity,
  APPROX_QUANTILES(total_diag_count, 100)[OFFSET(75)] AS p75_diag_intensity,
  APPROX_QUANTILES(total_diag_count, 100)[OFFSET(95)] AS p95_diag_intensity,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM general_counts;