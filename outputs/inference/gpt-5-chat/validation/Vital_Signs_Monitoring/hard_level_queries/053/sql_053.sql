WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    ie.intime,
    ie.outtime,
    a.hospital_expire_flag,
    ie.los,
    MAX(CASE WHEN LOWER(diag.long_title) LIKE '%shock%' THEN 1 ELSE 0 END) AS has_shock
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.subject_id = a.subject_id AND ie.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ie.subject_id = d.subject_id AND ie.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id,
           p.gender, p.anchor_age,
           ie.intime, ie.outtime, a.hospital_expire_flag, ie.los
),
vitals_24h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    AVG(IF(m.itemid IN (220052, 456) AND m.valuenum < 65, 1, NULL)) AS hypotension_burden,
    AVG(IF(m.itemid IN (220045, 211) AND m.valuenum > 100, 1, NULL)) AS tachy_burden
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` m
    ON c.stay_id = m.stay_id
   AND m.charttime >= c.intime 
   AND m.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
   AND m.valuenum IS NOT NULL
   AND m.itemid IN (220052, 456, 220045, 211)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
combined AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.has_shock,
    c.los,
    c.hospital_expire_flag,
    v.hypotension_burden,
    v.tachy_burden,
    (IFNULL(v.hypotension_burden,0) + IFNULL(v.tachy_burden,0)) AS composite_instability
  FROM cohort c
  LEFT JOIN vitals_24h v
    ON c.subject_id = v.subject_id 
   AND c.hadm_id = v.hadm_id
   AND c.stay_id = v.stay_id
),
stats_individual AS (
  SELECT
    has_shock,
    composite_instability,
    hypotension_burden,
    tachy_burden,
    los,
    hospital_expire_flag
  FROM combined
),
stats_with_percentiles AS (
  SELECT
    has_shock,
    COUNT(*) OVER(PARTITION BY has_shock) AS n_stays,
    AVG(composite_instability) OVER(PARTITION BY has_shock) AS mean_composite_instability,
    PERCENTILE_CONT(composite_instability, 0.25) OVER(PARTITION BY has_shock) AS p25_composite_instability,
    PERCENTILE_CONT(composite_instability, 0.5) OVER(PARTITION BY has_shock) AS p50_composite_instability,
    PERCENTILE_CONT(composite_instability, 0.75) OVER(PARTITION BY has_shock) AS p75_composite_instability,
    AVG(hypotension_burden) OVER(PARTITION BY has_shock) AS mean_hypotension_burden,
    PERCENTILE_CONT(hypotension_burden, 0.25) OVER(PARTITION BY has_shock) AS p25_hypotension_burden,
    PERCENTILE_CONT(hypotension_burden, 0.5) OVER(PARTITION BY has_shock) AS p50_hypotension_burden,
    PERCENTILE_CONT(hypotension_burden, 0.75) OVER(PARTITION BY has_shock) AS p75_hypotension_burden,
    AVG(tachy_burden) OVER(PARTITION BY has_shock) AS mean_tachy_burden,
    PERCENTILE_CONT(tachy_burden, 0.25) OVER(PARTITION BY has_shock) AS p25_tachy_burden,
    PERCENTILE_CONT(tachy_burden, 0.5) OVER(PARTITION BY has_shock) AS p50_tachy_burden,
    PERCENTILE_CONT(tachy_burden, 0.75) OVER(PARTITION BY has_shock) AS p75_tachy_burden,
    AVG(los) OVER(PARTITION BY has_shock) AS mean_icu_los,
    PERCENTILE_CONT(los, 0.25) OVER(PARTITION BY has_shock) AS p25_icu_los,
    PERCENTILE_CONT(los, 0.5) OVER(PARTITION BY has_shock) AS p50_icu_los,
    PERCENTILE_CONT(los, 0.75) OVER(PARTITION BY has_shock) AS p75_icu_los,
    AVG(hospital_expire_flag) OVER(PARTITION BY has_shock) AS mortality_rate
  FROM stats_individual
)
SELECT DISTINCT * FROM stats_with_percentiles
ORDER BY has_shock;