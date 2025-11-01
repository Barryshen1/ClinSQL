WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    CASE WHEN adm.deathtime IS NOT NULL OR (icu.outtime IS NOT NULL AND adm.discharge_location = 'DEAD/EXPIRED') THEN 1 ELSE 0 END AS mortality
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
    AND pat.anchor_age BETWEEN 45 AND 55
    AND LOWER(d_dx.long_title) LIKE '%heart failure%'
),

vitals AS (
  SELECT
    itemid,
    label
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) IN ('heart rate', 'map', 'respiratory rate')
),

vitals_72h AS (
  SELECT
    c.stay_id,
    c.los,
    c.mortality,
    ce.itemid,
    ce.valuenum,
    vit.label
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN
    vitals vit
    ON ce.itemid = vit.itemid
  WHERE
    ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
),

instability_score AS (
  SELECT
    stay_id,
    los,
    mortality,
    SUM(
      CASE WHEN label = 'Heart Rate' AND valuenum > 100 THEN 1 ELSE 0 END +
      CASE WHEN label = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END +
      CASE WHEN label = 'Respiratory Rate' AND valuenum > 20 THEN 1 ELSE 0 END
    ) AS instability_score
  FROM
    vitals_72h
  GROUP BY
    stay_id, los, mortality
),

percentile_99 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(99)] AS score_99th
  FROM
    instability_score
),

unstable_quartile AS (
  SELECT
    *,
    CASE WHEN instability_score >= (SELECT score_99th FROM percentile_99) THEN 1 ELSE 0 END AS in_top_quartile
  FROM
    instability_score
),

unstable_stats AS (
  SELECT
    AVG(CASE WHEN instability_score > 0 THEN 1.0 ELSE 0 END) AS avg_any_instability,
    AVG(CASE WHEN instability_score >= (SELECT score_99th FROM percentile_99) THEN 1.0 ELSE 0 END) AS pct_in_top_quartile,
    AVG(los) AS avg_icu_los,
    AVG(mortality) AS mortality_rate
  FROM
    unstable_quartile
  WHERE
    in_top_quartile = 1
),

overall_stats AS (
  SELECT
    AVG(CASE WHEN instability_score > 0 THEN 1.0 ELSE 0 END) AS avg_any_instability,
    AVG(los) AS avg_icu_los,
    AVG(mortality) AS mortality_rate
  FROM
    instability_score
)

SELECT
  (SELECT score_99th FROM percentile_99) AS instability_score_99th_percentile,
  u.avg_any_instability AS unstable_avg_any_instability,
  u.avg_icu_los AS unstable_avg_icu_los,
  u.mortality_rate AS unstable_mortality_rate,
  o.avg_any_instability AS overall_avg_any_instability,
  o.avg_icu_los AS overall_avg_icu_los,
  o.mortality_rate AS overall_mortality_rate
FROM
  unstable_stats u,
  overall_stats o;