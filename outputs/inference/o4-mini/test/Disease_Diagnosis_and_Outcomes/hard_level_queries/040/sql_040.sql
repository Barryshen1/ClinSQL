WITH ich_cohort AS (
  -- 1. Select distinct female inpatients aged 69-79 with ICH
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code    = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
    AND a.admission_type != 'NEWBORN'
),

cohort_with_scores AS (
  -- 2. Join to precomputed risk scores
  SELECT
    c.*,
    rs.risk_score
  FROM
    ich_cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.composite_risk_scores` rs
      ON c.subject_id = rs.subject_id
      AND c.hadm_id    = rs.hadm_id
),

quintiled AS (
  -- 3. Assign each admission to a quintile of risk score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM
    cohort_with_scores
),

outcomes AS (
  -- 4. Compute flags and LOS
  SELECT
    q.*,
    -- 30-day mortality flag
    CASE
      WHEN q.deathtime IS NOT NULL
       AND DATE_DIFF(DATE(q.deathtime), DATE(q.admittime), DAY) <= 30
      THEN 1 ELSE 0
    END AS mort30_flag,
    -- major complication flag (assume at least one row in major_complications)
    CASE
      WHEN mc.hadm_id IS NOT NULL THEN 1 ELSE 0
    END AS comp_flag,
    -- hospital LOS in days
    DATE_DIFF(DATE(q.dischtime), DATE(q.admittime), DAY) AS los_days
  FROM
    quintiled q
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.major_complications` mc
      ON q.subject_id = mc.subject_id
      AND q.hadm_id    = mc.hadm_id
)

-- 5. Aggregate by quintile
SELECT
  quintile,
  COUNT(*)                                         AS n,
  ROUND(100.0 * SUM(mort30_flag) / COUNT(*), 1)    AS pct_30d_mortality,
  ROUND(100.0 * SUM(comp_flag)    / COUNT(*), 1)    AS pct_major_complication,
  -- median LOS among survivors (mort30_flag = 0)
  APPROX_QUANTILES(
    IF(mort30_flag = 0, los_days, NULL),
    2
  )[OFFSET(1)]                                     AS median_survivor_los_days
FROM
  outcomes
GROUP BY
  quintile
ORDER BY
  quintile;