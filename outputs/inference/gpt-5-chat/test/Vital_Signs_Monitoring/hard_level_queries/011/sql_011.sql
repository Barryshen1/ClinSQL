WITH pneumonia_patients AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age AS age,
    a.hospital_expire_flag,
    ie.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ie.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND UPPER(d.long_title) LIKE '%PNEUMONIA%'
),

-- Placeholder — replace with actual computation of instability score from first 24h vitals/labs
instability_scores AS (
  SELECT
    stay_id,
    CAST(ROUND(icu_los * 10, 1) AS FLOAT64) AS instability_score
  FROM pneumonia_patients
),

scored AS (
  SELECT
    p.*,
    s.instability_score,
    PERCENT_RANK() OVER (ORDER BY s.instability_score) AS percent_rank,
    CUME_DIST() OVER (ORDER BY s.instability_score) AS cume_dist,
    -- Percent rank in descending order to get top decile easily
    PERCENT_RANK() OVER (ORDER BY s.instability_score DESC) AS percent_rank_desc
  FROM pneumonia_patients p
  JOIN instability_scores s USING (stay_id)
),

given_score AS (
  SELECT
    instability_score,
    percent_rank,
    cume_dist
  FROM scored
  WHERE instability_score = 60
  LIMIT 1
),

top_decile AS (
  SELECT *
  FROM scored
  WHERE percent_rank_desc < 0.1
)

SELECT
  ANY_VALUE(g.instability_score) AS given_score,
  ANY_VALUE(g.percent_rank) AS given_score_percent_rank,
  ANY_VALUE(g.cume_dist) AS given_score_cume_dist,
  AVG(t.icu_los) AS top_decile_mean_icu_los,
  SUM(t.hospital_expire_flag) / COUNT(*) AS top_decile_mortality_rate
FROM given_score g
CROSS JOIN top_decile t;