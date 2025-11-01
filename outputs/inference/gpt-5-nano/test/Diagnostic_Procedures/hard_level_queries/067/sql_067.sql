WITH heart_failure_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

-- Eligible ICU stays for male patients aged ~70-80 with heart failure
eligible_icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = i.subject_id
  WHERE (p.gender IN ('M', 'm'))
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
    AND i.hadm_id IN (SELECT hadm_id FROM heart_failure_hadm)
),

-- Diagnostic intensity: number of labevents in first 72 hours of ICU stay
per_stay_intensity AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id,
         COUNT(le.labevent_id) AS diagnostic_intensity
  FROM eligible_icu_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = s.subject_id
   AND le.hadm_id = s.hadm_id
   AND le.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
),

-- Intensity statistics (split into scalar subqueries to avoid aggregation/analytic mix issues)
mean_intensity AS (
  SELECT AVG(diagnostic_intensity) AS mean_intensity
  FROM per_stay_intensity
),

median_intensity AS (
  -- Use a windowed percentile to obtain the 50th percentile, returned as a single scalar
  SELECT PERCENTILE_CONT(diagnostic_intensity, 0.5) OVER () AS median_intensity
  FROM per_stay_intensity
  LIMIT 1
),

p75_intensity AS (
  SELECT PERCENTILE_CONT(diagnostic_intensity, 0.75) OVER () AS p75_intensity
  FROM per_stay_intensity
  LIMIT 1
),

p95_intensity AS (
  SELECT PERCENTILE_CONT(diagnostic_intensity, 0.95) OVER () AS p95_intensity
  FROM per_stay_intensity
  LIMIT 1
),

-- General ICU population metrics: mean ICU LOS and hospital mortality
general_stats AS (
  SELECT
     AVG(i.los) AS mean_los,
     AVG(CASE WHEN a.deathtime IS NOT NULL THEN 1.0 ELSE 0.0 END) AS hospital_mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = i.hadm_id
)

-- Final: combine target group intensity metrics with general ICU LOS and mortality
SELECT
  m.mean_intensity AS mean_intensity,
  mi.median_intensity AS median_intensity,
  p75.p75_intensity AS p75_intensity,
  p95.p95_intensity AS p95_intensity,
  g.mean_los AS general_mean_los,
  g.hospital_mortality_rate AS general_hospital_mortality
FROM mean_intensity m
CROSS JOIN median_intensity mi
CROSS JOIN p75_intensity p75
CROSS JOIN p95_intensity p95
CROSS JOIN general_stats g
LIMIT 1;