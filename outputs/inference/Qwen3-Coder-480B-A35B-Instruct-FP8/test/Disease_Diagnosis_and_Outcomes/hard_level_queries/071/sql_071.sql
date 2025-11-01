WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    p.dod,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    CASE
      WHEN a.deathtime IS NOT NULL AND a.deathtime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 90 DAY) THEN 1
      WHEN p.dod IS NOT NULL AND p.dod BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 90 DAY) THEN 1
      ELSE 0
    END AS mortality_90d
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND d.long_title LIKE '%Acute myocardial infarction%'
),

-- Simplified risk score using GCS (example component)
gcs_scores AS (
  SELECT
    stay_id,
    MIN(CASE WHEN itemid IN (220733, 223900, 223901) THEN valuenum ELSE NULL END) AS gcs_min
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (220733, 223900, 223901) -- GCS components
    AND valuenum IS NOT NULL
  GROUP BY
    stay_id
),

risk_scores AS (
  SELECT
    c.*,
    COALESCE(g.gcs_min, 15) AS gcs_score
  FROM
    cohort c
  LEFT JOIN
    gcs_scores g
  ON
    c.stay_id = g.stay_id
),

stats AS (
  SELECT
    APPROX_QUANTILES(gcs_score, 100) AS percentile_gcs,
    APPROX_QUANTILES(gcs_score, 4)[OFFSET(2)] AS median_gcs,
    APPROX_QUANTILES(gcs_score, 4)[OFFSET(1)] AS q1_gcs,
    APPROX_QUANTILES(gcs_score, 4)[OFFSET(3)] AS q3_gcs,
    AVG(CAST(mortality_90d AS FLOAT64)) AS mortality_rate_90d
  FROM
    risk_scores
)

SELECT
  s.median_gcs,
  s.q1_gcs,
  s.q3_gcs,
  s.mortality_rate_90d,
  s.percentile_gcs[ORDINAL(25)] AS p25_gcs,
  s.percentile_gcs[ORDINAL(75)] AS p75_gcs,
  s.percentile_gcs[ORDINAL(90)] AS p90_gcs
FROM
  stats s;