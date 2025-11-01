WITH
-- 1. Get male ICU patients aged 89-99
male_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- 2. Identify ischemic stroke admissions (ICD-10 I63.x)
ischemic_stroke_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I63'))
),

-- 3. Map vital sign itemids (from d_items)
vital_signs AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) IN (
      'heart rate', 'hr',
      'systolic blood pressure', 'sbp',
      'respiratory rate', 'rr',
      'spo2', 'o2 saturation',
      'temperature', 'temp'
    )
),

-- 4. Get abnormal episodes in first 48h for each ICU stay
abnormal_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    ds.label,
    -- Define abnormality per vital sign
    CASE
      WHEN LOWER(ds.label) IN ('heart rate', 'hr') AND (ce.valuenum < 40 OR ce.valuenum > 130) THEN 1
      WHEN LOWER(ds.label) IN ('systolic blood pressure', 'sbp') AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
      WHEN LOWER(ds.label) IN ('respiratory rate', 'rr') AND (ce.valuenum < 8 OR ce.valuenum > 30) THEN 1
      WHEN LOWER(ds.label) IN ('spo2', 'o2 saturation') AND (ce.valuenum < 90) THEN 1
      WHEN LOWER(ds.label) IN ('temperature', 'temp') AND (ce.valuenum < 35 OR ce.valuenum > 39) THEN 1
      ELSE 0
    END AS is_abnormal
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN vital_signs ds ON ce.itemid = ds.itemid
    JOIN male_icu icu ON ce.stay_id = icu.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
),

-- 5. Instability score per ICU stay (sum of abnormal episodes)
instability_scores AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    icu.anchor_age,
    icu.gender,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_ischemic_stroke,
    COUNTIF(ae.is_abnormal = 1) AS instability_score
  FROM
    male_icu icu
    LEFT JOIN ischemic_stroke_hadm s ON icu.hadm_id = s.hadm_id
    LEFT JOIN abnormal_events ae ON icu.stay_id = ae.stay_id
  GROUP BY
    icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los, icu.anchor_age, icu.gender, is_ischemic_stroke
),

-- 6. Add mortality flag and LOS in hours
instability_scores_with_mortality AS (
  SELECT
    iscores.*,
    a.hospital_expire_flag,
    iscores.los * 24 AS icu_los_hours
  FROM
    instability_scores iscores
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON iscores.hadm_id = a.hadm_id
),

-- 7. Calculate 95th percentile instability score for ischemic stroke
stroke_instability_percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 20)[19] AS instability_95th
  FROM
    instability_scores_with_mortality
  WHERE
    is_ischemic_stroke = 1
),

-- 8. Calculate 75th percentile (top quartile) instability score for all
quartile_cutoff AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[3] AS instability_75th
  FROM
    instability_scores_with_mortality
),

-- 9. Select top quartile patients, group by ischemic stroke vs general ICU
top_quartile_summary AS (
  SELECT
    CASE WHEN is_ischemic_stroke = 1 THEN 'Ischemic Stroke' ELSE 'General ICU' END AS group_type,
    COUNT(*) AS N,
    AVG(instability_score) AS mean_instability,
    AVG(instability_score) AS mean_abnormal_episodes,
    AVG(icu_los_hours) AS mean_icu_los_hours,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    instability_scores_with_mortality, quartile_cutoff
  WHERE
    instability_score >= quartile_cutoff.instability_75th
  GROUP BY
    group_type
)

-- Final output: 95th percentile for stroke, and top quartile summary
SELECT
  '95th_percentile_stroke_instability' AS metric,
  STRUCT(
    CAST(NULL AS INT64) AS N,
    CAST(stroke_instability_percentile.instability_95th AS FLOAT64) AS mean_instability,
    CAST(NULL AS FLOAT64) AS mean_abnormal_episodes,
    CAST(NULL AS FLOAT64) AS mean_icu_los_hours,
    CAST(NULL AS FLOAT64) AS mortality_rate
  ) AS value
FROM stroke_instability_percentile

UNION ALL

SELECT
  group_type AS metric,
  STRUCT(N, mean_instability, mean_abnormal_episodes, mean_icu_los_hours, mortality_rate) AS value
FROM top_quartile_summary;