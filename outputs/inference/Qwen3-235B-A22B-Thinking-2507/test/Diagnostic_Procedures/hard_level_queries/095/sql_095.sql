WITH cohort_base AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code = '4151') 
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
        )
    )
),
lab_counts AS (
  SELECT 
    l.hadm_id,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort_base c 
    ON l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.intime AND c.intime + INTERVAL '24' HOUR
  GROUP BY l.hadm_id
),
micro_counts AS (
  SELECT 
    m.hadm_id,
    COUNT(*) AS micro_count
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
  INNER JOIN cohort_base c 
    ON m.hadm_id = c.hadm_id
  WHERE m.charttime BETWEEN c.intime AND c.intime + INTERVAL '24' HOUR
  GROUP BY m.hadm_id
),
cohort_scores AS (
  SELECT 
    c.stay_id,
    c.hadm_id,
    c.icu_los,
    c.hospital_expire_flag,
    COALESCE(lc.lab_count, 0) + COALESCE(mc.micro_count, 0) AS diag_score
  FROM cohort_base c
  LEFT JOIN lab_counts lc ON c.hadm_id = lc.hadm_id
  LEFT JOIN micro_counts mc ON c.hadm_id = mc.hadm_id
),
general_population AS (
  SELECT 
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
),
cohort_stats AS (
  SELECT 
    APPROX_QUANTILES(diag_score, 1000)[OFFSET(750)] AS cohort_75th_percentile,
    APPROX_QUANTILES(icu_los, 1000)[OFFSET(500)] AS cohort_median_los,
    AVG(hospital_expire_flag) AS cohort_mortality_rate
  FROM cohort_scores
),
general_stats AS (
  SELECT 
    APPROX_QUANTILES(icu_los, 1000)[OFFSET(500)] AS general_median_los,
    AVG(hospital_expire_flag) AS general_mortality_rate
  FROM general_population
)
SELECT 
  cs.cohort_75th_percentile,
  cs.cohort_median_los,
  gs.general_median_los,
  cs.cohort_mortality_rate,
  gs.general_mortality_rate
FROM cohort_stats cs, general_stats gs;