WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.los AS icu_los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    adm.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 88 AND 98
),
instability_scores AS (
  SELECT
    c.stay_id,
    c.hadm_id,
    c.icu_los,
    c.hospital_expire_flag,
    SUM(CASE WHEN di.lownormalvalue IS NOT NULL AND di.highnormalvalue IS NOT NULL 
              AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue)
             THEN 1 ELSE 0 END) AS instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime <= c.intime + INTERVAL '72' HOUR
    AND ce.valuenum IS NOT NULL
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  GROUP BY c.stay_id, c.hadm_id, c.icu_los, c.hospital_expire_flag
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM instability_scores
)
SELECT
  -- Percentile of 85
  COUNTIF(instability_score <= 85) * 100.0 / COUNT(*) AS percentile_85,
  -- ICU LOS for most unstable quartile (quartile 1)
  AVG(CASE WHEN instability_quartile = 1 THEN icu_los END) AS avg_icu_los_top_quartile,
  -- Hospital mortality for most unstable quartile
  AVG(CASE WHEN instability_quartile = 1 THEN hospital_expire_flag END) AS mortality_top_quartile
FROM quartiles;