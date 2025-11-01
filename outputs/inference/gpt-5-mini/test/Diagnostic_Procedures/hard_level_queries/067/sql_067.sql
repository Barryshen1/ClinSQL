WITH
-- ICU stays
icustays AS (
  SELECT *
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- lab events during first 72 hours of each ICU stay
lab_events72 AS (
  SELECT icu.stay_id, le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN icustays icu
    ON le.subject_id = icu.subject_id
   AND le.hadm_id = icu.hadm_id
  WHERE le.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
),

-- microbiology events during first 72 hours of each ICU stay
micro_events72 AS (
  SELECT icu.stay_id, me.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
  JOIN icustays icu
    ON me.subject_id = icu.subject_id
   AND me.hadm_id = icu.hadm_id
  WHERE me.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
),

-- union of diagnostic events (each row = one event occurrence)
events_union AS (
  SELECT stay_id FROM lab_events72
  UNION ALL
  SELECT stay_id FROM micro_events72
),

-- diagnostic counts per stay (0 if none)
diag_counts AS (
  SELECT stay_id, COUNT(*) AS diag_count
  FROM events_union
  GROUP BY stay_id
),

stays_with_counts AS (
  SELECT s.*, COALESCE(d.diag_count, 0) AS diag_count
  FROM icustays s
  LEFT JOIN diag_counts d USING(stay_id)
),

-- identify admissions with heart failure by matching diagnosis long_title
heart_failure_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

-- enrich stays with patient demographics, admission mortality, and heart-failure flag
stays_enriched AS (
  SELECT swc.*,
         p.gender,
         p.anchor_age,
         a.hospital_expire_flag,
         CASE WHEN hf.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS heart_failure
  FROM stays_with_counts swc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON swc.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON swc.hadm_id = a.hadm_id AND swc.subject_id = a.subject_id
  LEFT JOIN heart_failure_hadm hf
    ON swc.hadm_id = hf.hadm_id
)

-- final aggregations: cohort (male, age 70-80, heart failure) vs all ICU
SELECT
  'HF_males_70_80' AS cohort,
  AVG(diag_count) AS mean_diag,
  APPROX_QUANTILES(diag_count, 100)[OFFSET(50)] AS p50_diag,
  APPROX_QUANTILES(diag_count, 100)[OFFSET(75)] AS p75_diag,
  APPROX_QUANTILES(diag_count, 100)[OFFSET(95)] AS p95_diag,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality
FROM stays_enriched
WHERE gender = 'M'
  AND anchor_age BETWEEN 70 AND 80
  AND heart_failure = 1

UNION ALL

SELECT
  'All_ICU' AS cohort,
  AVG(diag_count) AS mean_diag,
  APPROX_QUANTILES(diag_count, 100)[OFFSET(50)] AS p50_diag,
  APPROX_QUANTILES(diag_count, 100)[OFFSET(75)] AS p75_diag,
  APPROX_QUANTILES(diag_count, 100)[OFFSET(95)] AS p95_diag,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality
FROM stays_enriched;