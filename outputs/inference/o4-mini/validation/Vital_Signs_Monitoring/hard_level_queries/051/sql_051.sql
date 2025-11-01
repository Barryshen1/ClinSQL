WITH cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    a.hospital_expire_flag,
    CASE 
      WHEN s.subject_id IS NOT NULL THEN 1
      ELSE 0
    END AS is_stroke
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id
   AND i.hadm_id     = a.hadm_id
  LEFT JOIN (
    SELECT DISTINCT
      dx.subject_id,
      dx.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON dx.icd_code    = dicd.icd_code
     AND dx.icd_version = dicd.icd_version
    WHERE
      LOWER(dicd.long_title) LIKE '%ischemic stroke%'
  ) s
    ON i.subject_id = s.subject_id
   AND i.hadm_id     = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),
abnormal_events AS (
  SELECT
    c.stay_id,
    COUNT(1) AS instability_score_48h,
    COUNT(DISTINCT ce.itemid) AS abnormal_episodes
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
   AND c.hadm_id     = ce.hadm_id
   AND c.stay_id     = ce.stay_id
   AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    SAFE_CAST(ce.valuenum AS FLOAT64) IS NOT NULL
    AND (
      ce.valuenum < di.lownormalvalue
      OR ce.valuenum > di.highnormalvalue
    )
  GROUP BY
    c.stay_id
),
scores AS (
  SELECT
    c.*,
    COALESCE(ae.instability_score_48h, 0) AS instability_score_48h,
    COALESCE(ae.abnormal_episodes, 0)   AS abnormal_episodes
  FROM
    cohort c
  LEFT JOIN
    abnormal_events ae
    ON c.stay_id = ae.stay_id
),
stroke_scores AS (
  SELECT
    instability_score_48h
  FROM
    scores
  WHERE
    is_stroke = 1
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score_48h, 100)[OFFSET(95)] AS p95,
    APPROX_QUANTILES(instability_score_48h,   4)[OFFSET(3)] AS q4_threshold
  FROM
    stroke_scores
),
top_quartile AS (
  SELECT
    s.*,
    p.p95,
    p.q4_threshold
  FROM
    scores s
  CROSS JOIN
    percentiles p
  WHERE
    s.instability_score_48h >= p.q4_threshold
)
SELECT
  CASE 
    WHEN is_stroke = 1 THEN 'Ischemic Stroke'
    ELSE 'General ICU'
  END AS cohort,
  COUNT(1)                                AS N,
  ROUND(AVG(instability_score_48h), 2)    AS mean_instability_score,
  ROUND(AVG(abnormal_episodes), 2)        AS mean_abnormal_episodes,
  ROUND(AVG(los * 24), 2)                 AS mean_ICU_LOS_hours,
  ROUND(AVG(hospital_expire_flag), 3)     AS mortality_rate
FROM
  top_quartile
GROUP BY
  cohort
ORDER BY
  cohort;