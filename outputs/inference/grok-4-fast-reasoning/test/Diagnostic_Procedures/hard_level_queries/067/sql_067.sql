WITH hf_admissions AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND (
      icd_code LIKE '428%' OR
      icd_code IN ('39891', '40201', '40211', '40291', '40401', '40411', '40491', '4254')
    ))
    OR
    (icd_version = 10 AND (
      icd_code LIKE 'I50%' OR
      icd_code IN ('I0981', 'I110', 'I130', 'I132')
    ))
  )
),
icu_with_demo AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    p.gender,
    FLOOR(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
),
cohort_stays AS (
  SELECT s.*, 1 AS has_hf
  FROM icu_with_demo s
  INNER JOIN hf_admissions h ON s.subject_id = h.subject_id AND s.hadm_id = h.hadm_id
  WHERE s.gender = 'M'
    AND s.age BETWEEN 70 AND 80
),
general_stays AS (
  SELECT *
  FROM icu_with_demo
  WHERE age >= 18
),
intensity_data_cohort AS (
  SELECT 
    cs.stay_id,
    COALESCE(COUNT(le.labevent_id), 0) AS diag_intensity
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON le.subject_id = cs.subject_id
    AND le.hadm_id = cs.hadm_id
    AND le.charttime >= cs.intime
    AND le.charttime < TIMESTAMP_ADD(cs.intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
  GROUP BY cs.stay_id
),
cohort_intensity_stats AS (
  SELECT 
    AVG(diag_intensity) AS mean_intensity,
    PERCENTILE_CONT(diag_intensity, 0.5) AS median_intensity,
    PERCENTILE_CONT(diag_intensity, 0.75) AS p75_intensity,
    PERCENTILE_CONT(diag_intensity, 0.95) AS p95_intensity
  FROM intensity_data_cohort
),
los_stats AS (
  SELECT AVG(los) AS mean_los
  FROM cohort_stays
),
mortality_stats AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) * 1.0 / 
    COUNT(DISTINCT hadm_id) AS mortality_rate
  FROM cohort_stays
),
intensity_data_general AS (
  SELECT 
    gs.stay_id,
    COALESCE(COUNT(le.labevent_id), 0) AS diag_intensity
  FROM general_stays gs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON le.subject_id = gs.subject_id
    AND le.hadm_id = gs.hadm_id
    AND le.charttime >= gs.intime
    AND le.charttime < TIMESTAMP_ADD(gs.intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
  GROUP BY gs.stay_id
),
general_intensity_stats AS (
  SELECT 
    AVG(diag_intensity) AS mean_intensity,
    PERCENTILE_CONT(diag_intensity, 0.5) AS median_intensity,
    PERCENTILE_CONT(diag_intensity, 0.75) AS p75_intensity,
    PERCENTILE_CONT(diag_intensity, 0.95) AS p95_intensity
  FROM intensity_data_general
)
SELECT 
  cis.mean_intensity AS cohort_mean_intensity,
  cis.median_intensity AS cohort_median_intensity,
  cis.p75_intensity AS cohort_p75_intensity,
  cis.p95_intensity AS cohort_p95_intensity,
  ls.mean_los AS cohort_mean_los,
  ms.mortality_rate AS cohort_mortality_rate,
  gis.mean_intensity AS general_mean_intensity,
  gis.median_intensity AS general_median_intensity,
  gis.p75_intensity AS general_p75_intensity,
  gis.p95_intensity AS general_p95_intensity
FROM cohort_intensity_stats cis, los_stats ls, mortality_stats ms, general_intensity_stats gis
LIMIT 1;