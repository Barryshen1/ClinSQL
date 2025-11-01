WITH cohort AS (
  -- 1. Base cohort: female inpatients 75-85 with COPD exacerbation
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND LOWER(dd.long_title) LIKE '%copd%'
    AND LOWER(dd.long_title) LIKE '%exacerb%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    p.anchor_age
),
with_scores AS (
  -- 2. Compute risk_score and complication flag using window functions
  SELECT
    c.*,
    COUNT(*) OVER (PARTITION BY c.subject_id, c.hadm_id) AS risk_score,
    CASE WHEN COUNT(*) OVER (PARTITION BY c.subject_id, c.hadm_id) > 1 THEN 1 ELSE 0 END AS complication
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      ON c.subject_id = d2.subject_id
     AND c.hadm_id    = d2.hadm_id
),
quartiled AS (
  -- 3. Assign quartiles by risk_score
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM
    with_scores
),
outcomes AS (
  -- 4. Compute death within 90 days and carry forward needed fields
  SELECT
    q.*,
    CASE
      WHEN q.dod IS NOT NULL
       AND DATE_DIFF(DATE(q.dod), DATE(q.dischtime), DAY) BETWEEN 0 AND 90
      THEN 1 ELSE 0
    END AS death90
  FROM
    quartiled q
),
agg_by_quartile AS (
  -- 5. Aggregate by quartile without correlated subqueries
  SELECT
    risk_quartile,
    COUNT(*) AS n_patients,
    ROUND(100.0 * AVG(CAST(death90 AS FLOAT64)), 2) AS pct_90day_mortality,
    ROUND(100.0 * AVG(CAST(complication AS FLOAT64)), 2) AS pct_major_complication,
    -- median LOS among survivors
    APPROX_QUANTILES(
      IF(death90 = 0, los, NULL), 2
    )[OFFSET(1)] AS median_los_survivors
  FROM
    outcomes
  GROUP BY
    risk_quartile
),
overall AS (
  -- 6. Compute overall 90-day mortality for the full cohort
  SELECT
    ROUND(100.0 * AVG(CAST(death90 AS FLOAT64)), 2) AS overall_pct_90day_mortality
  FROM
    outcomes
)
-- Final select: join quartile aggregates and cross‐join the overall rate
SELECT
  q.risk_quartile,
  q.n_patients,
  q.pct_90day_mortality,
  q.pct_major_complication,
  q.median_los_survivors,
  o.overall_pct_90day_mortality
FROM
  agg_by_quartile q
CROSS JOIN
  overall o
ORDER BY
  q.risk_quartile;