WITH female_adms AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    CASE 
      WHEN a.deathtime IS NOT NULL
       AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30
      THEN 1 ELSE 0
    END AS died_30d,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
cardiac_arrest_adms AS (
  SELECT DISTINCT
    da.subject_id,
    da.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` da
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING(icd_code, icd_version)
  WHERE
    da.icd_version = 10
    AND da.icd_code LIKE 'I46%'
),
cohort AS (
  SELECT
    f.*,
    rs.risk_score
  FROM
    female_adms f
    JOIN cardiac_arrest_adms ca
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.risk_scores` rs
      USING(subject_id, hadm_id)
),
with_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM
    cohort
),
complications AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.quartile,
    q.died_30d,
    q.los_days,
    MAX(CASE
      WHEN d.icd_version = 10
       AND REGEXP_CONTAINS(d.icd_code, r'^I\d{2}')
       AND NOT REGEXP_CONTAINS(d.icd_code, r'^I46')
      THEN 1 ELSE 0
    END) AS cardio_comp,
    MAX(CASE
      WHEN d.icd_version = 10
       AND REGEXP_CONTAINS(d.icd_code, r'^G\d{2}')
      THEN 1 ELSE 0
    END) AS neuro_comp
  FROM
    with_quartiles q
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
  GROUP BY
    q.subject_id, q.hadm_id, q.quartile, q.died_30d, q.los_days
),
quartile_stats AS (
  SELECT
    quartile,
    COUNT(*) AS n_adm,
    100.0 * SUM(died_30d) / COUNT(*) AS mortality_30d_pct,
    100.0 * SUM(cardio_comp) / COUNT(*) AS cardio_comp_pct,
    100.0 * SUM(neuro_comp) / COUNT(*) AS neuro_comp_pct,
    -- median LOS among survivors
    APPROX_QUANTILES(
      CASE WHEN died_30d = 0 THEN los_days ELSE NULL END,
      2
    )[OFFSET(1)] AS median_survivor_los
  FROM
    complications
  GROUP BY
    quartile
),
baseline AS (
  SELECT
    100.0 * SUM(died_30d) / COUNT(*) AS baseline_30d_mortality_pct
  FROM
    female_adms
)
SELECT
  q.quartile,
  q.n_adm,
  q.mortality_30d_pct,
  q.cardio_comp_pct,
  q.neuro_comp_pct,
  q.median_survivor_los,
  b.baseline_30d_mortality_pct
FROM
  quartile_stats q
  CROSS JOIN baseline b
ORDER BY
  quartile;