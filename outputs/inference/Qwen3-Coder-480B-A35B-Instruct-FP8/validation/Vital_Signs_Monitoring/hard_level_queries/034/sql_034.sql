WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag AS mortality
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
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND LOWER(d_dx.long_title) LIKE '%mixed%schock%'
),

-- Extract MAP and HR from chartevents in first 48 hours
vitals AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label LIKE '%mean%arterial%pressure%' THEN ce.valuenum ELSE NULL END) AS map,
    MAX(CASE WHEN di.label LIKE '%heart%rate%' THEN ce.valuenum ELSE NULL END) AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime <= icu.intime + INTERVAL 48 HOUR
    AND (
      LOWER(di.label) LIKE '%mean%arterial%pressure%'
      OR LOWER(di.label) LIKE '%heart%rate%'
    )
  GROUP BY
    ce.stay_id, ce.charttime
),

-- Compute instability score per stay
instability_scores AS (
  SELECT
    stay_id,
    COUNT(*) AS time_points,
    SUM(CASE WHEN map < 65 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN heart_rate > 120 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(
      CASE WHEN map < 65 THEN 1 ELSE 0 END +
      CASE WHEN heart_rate > 120 THEN 1 ELSE 0 END
    ) AS instability_score
  FROM
    vitals
  WHERE
    map IS NOT NULL AND heart_rate IS NOT NULL
  GROUP BY
    stay_id
),

-- Add scores to cohort
cohort_with_scores AS (
  SELECT
    c.*,
    COALESCE(i.instability_score, 0) AS instability_score,
    COALESCE(i.hypotension_count, 0) AS hypotension_count,
    COALESCE(i.tachycardia_count, 0) AS tachycardia_count
  FROM
    cohort c
  LEFT JOIN
    instability_scores i
    ON c.stay_id = i.stay_id
),

-- Compute 95th percentile of instability score
percentile_95 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS score_95th
  FROM
    cohort_with_scores
),

-- Assign top decile vs rest
scored_cohort AS (
  SELECT
    c.*,
    CASE
      WHEN c.instability_score >= (SELECT score_95th FROM percentile_95) THEN 'Top Decile'
      ELSE 'Rest'
    END AS score_group
  FROM
    cohort_with_scores c
)

-- Final comparison
SELECT
  score_group,
  COUNT(*) AS n_stays,
  AVG(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) AS prop_with_instability,
  AVG(CASE WHEN hypotension_count > 0 THEN 1 ELSE 0 END) AS prop_with_hypotension,
  AVG(CASE WHEN tachycardia_count > 0 THEN 1 ELSE 0 END) AS prop_with_tachycardia,
  AVG(icu_los) AS avg_icu_los,
  AVG(mortality) AS mortality_rate
FROM
  scored_cohort
GROUP BY
  score_group
ORDER BY
  score_group;