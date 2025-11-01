WITH trauma_admissions AS (
  -- Identify admissions with >=2 distinct trauma diagnoses
  SELECT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%trauma%' OR LOWER(d.long_title) LIKE '%injury%'
  GROUP BY
    di.hadm_id
  HAVING
    COUNT(DISTINCT di.icd_code) >= 2
),

first_icu_stays AS (
  -- Get first ICU stays for male patients aged 68–78 with multi-trauma
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
      ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
      ON icu.hadm_id = adm.hadm_id
  JOIN
    trauma_admissions ta
      ON icu.hadm_id = ta.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) = 1
),

vitals AS (
  -- Map vital signs to itemids
  SELECT
    itemid,
    label
  FROM
    physionet-data.mimiciv_3_1_icu.d_items
  WHERE
    LOWER(label) IN ('heart rate', 'respiratory rate', 'systolic blood pressure')
),

instability_scores AS (
  -- Compute instability score for each first ICU stay
  SELECT
    f.stay_id,
    f.los,
    f.hospital_expire_flag,
    COUNT(CASE WHEN di.label = 'Heart Rate' AND ce.valuenum > 130 THEN 1 END) AS tachycardia_episodes,
    COUNT(CASE WHEN di.label = 'Systolic blood pressure' AND ce.valuenum < 90 THEN 1 END) AS hypotension_episodes,
    COUNT(CASE WHEN di.label = 'Respiratory rate' AND ce.valuenum > 30 THEN 1 END) AS tachypnea_episodes
  FROM
    first_icu_stays f
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
      ON f.stay_id = ce.stay_id
  JOIN
    vitals di
      ON ce.itemid = di.itemid
  WHERE
    ce.charttime >= f.intime
    AND ce.charttime <= DATETIME_ADD(f.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    f.stay_id, f.los, f.hospital_expire_flag
),

score_summary AS (
  SELECT
    stay_id,
    tachycardia_episodes + hypotension_episodes + tachypnea_episodes AS instability_score,
    tachycardia_episodes,
    hypotension_episodes,
    tachypnea_episodes,
    los,
    hospital_expire_flag
  FROM
    instability_scores
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS score_quartile,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS score_percentile
  FROM
    score_summary
),

quartile_stats AS (
  SELECT
    score_quartile,
    COUNT(*) AS stay_count,
    AVG(instability_score) AS mean_instability_score,
    AVG(los) AS mean_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    quartiles
  GROUP BY
    score_quartile
),

top_decile AS (
  SELECT
    *
  FROM
    quartiles
  WHERE
    score_percentile >= 0.9
),

top_decile_stats AS (
  SELECT
    5 AS score_quartile,
    COUNT(*) AS stay_count,
    AVG(instability_score) AS mean_instability_score,
    AVG(los) AS mean_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(tachycardia_episodes) AS mean_tachycardia_episodes,
    AVG(hypotension_episodes) AS mean_hypotension_episodes,
    AVG(tachypnea_episodes) AS mean_tachypnea_episodes
  FROM
    top_decile
)

-- Final output
SELECT
  score_quartile,
  stay_count,
  mean_instability_score,
  mean_icu_los,
  mortality_rate,
  NULL AS mean_tachycardia_episodes,
  NULL AS mean_hypotension_episodes,
  NULL AS mean_tachypnea_episodes
FROM
  quartile_stats
UNION ALL
SELECT
  score_quartile,
  stay_count,
  mean_instability_score,
  mean_icu_los,
  mortality_rate,
  mean_tachycardia_episodes,
  mean_hypotension_episodes,
  mean_tachypnea_episodes
FROM
  top_decile_stats
ORDER BY
  score_quartile;