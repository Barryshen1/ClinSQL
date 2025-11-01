WITH sepsis_icu_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND LOWER(d_dx.long_title) LIKE '%sepsis%'
),

-- Approximate SOFA score using chartevents
sofa_scores AS (
  SELECT
    ce.stay_id,
    MAX(CASE WHEN itemid IN (227428, 223835) THEN valuenum ELSE NULL END) AS sofa_respiratory, -- PaO2/FiO2
    MAX(CASE WHEN itemid IN (227442, 220635) THEN valuenum ELSE NULL END) AS sofa_coagulation, -- Platelets
    MAX(CASE WHEN itemid IN (227444, 226770) THEN valuenum ELSE NULL END) AS sofa_liver, -- Bilirubin
    MAX(CASE WHEN itemid IN (227010, 223901) THEN valuenum ELSE NULL END) AS sofa_cardio, -- MAP or dopamine
    MAX(CASE WHEN itemid IN (227009, 226755) THEN valuenum ELSE NULL END) AS sofa_cns, -- GCS
    MAX(CASE WHEN itemid IN (227443, 220615) THEN valuenum ELSE NULL END) AS sofa_renal -- Creatinine
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    sepsis_icu_cohort coh
    ON ce.stay_id = coh.stay_id
  WHERE
    ce.charttime >= coh.intime
    AND ce.charttime <= DATETIME_ADD(coh.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
),

-- Compute total SOFA score (sum of component scores, capped at max per component)
sofa_total AS (
  SELECT
    stay_id,
    LEAST(4, GREATEST(0, sofa_respiratory)) +
    LEAST(4, GREATEST(0, sofa_coagulation)) +
    LEAST(4, GREATEST(0, sofa_liver)) +
    LEAST(4, GREATEST(0, sofa_cardio)) +
    LEAST(4, GREATEST(0, sofa_cns)) +
    LEAST(4, GREATEST(0, sofa_renal)) AS sofa_score
  FROM
    sofa_scores
),

-- Add back cohort info
full_cohort AS (
  SELECT
    coh.*,
    sofa.sofa_score
  FROM
    sepsis_icu_cohort coh
  JOIN
    sofa_total sofa
    ON coh.stay_id = sofa.stay_id
  WHERE
    sofa.sofa_score IS NOT NULL
),

-- Percentile rank of score = 85
percentile_rank AS (
  SELECT
    PERCENT_RANK() OVER (ORDER BY sofa_score) AS pct_rank_85
  FROM
    full_cohort
  WHERE
    sofa_score <= 85
  ORDER BY
    sofa_score DESC
  LIMIT 1
),

-- Quartile 4 stats
quartile_stats AS (
  SELECT
    sofa_score,
    icu_los,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY sofa_score) AS sofa_quartile
  FROM
    full_cohort
),

q4_stats AS (
  SELECT
    AVG(icu_los) AS mean_icu_los_q4,
    AVG(hospital_expire_flag) AS mortality_q4
  FROM
    quartile_stats
  WHERE
    sofa_quartile = 4
)

-- Final output
SELECT
  (SELECT pct_rank_85 FROM percentile_rank) AS percentile_rank_85,
  (SELECT mean_icu_los_q4 FROM q4_stats) AS mean_icu_los_q4,
  (SELECT mortality_q4 FROM q4_stats) AS mortality_q4;