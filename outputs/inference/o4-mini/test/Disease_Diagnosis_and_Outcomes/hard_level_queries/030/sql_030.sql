WITH
-- 1. Base cohort: male, age 64-74, upper GI bleeding primary diagnosis
base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx_pri
    ON a.hadm_id = dx_pri.hadm_id
       AND dx_pri.seq_num = 1
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND dx_pri.icd_code IN ('K92.0','K92.1','K92.2')  -- upper GI bleeding codes
),
-- 2. Compute per-admission metrics
hadm_metrics AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    -- count all diagnoses
    COUNT(dx.icd_code) AS diagnosis_count,
    -- major complication flag
    MAX(
      CASE
        WHEN dx.icd_code IN (
             -- replace with your actual major complication codes
             '998.2','998.3','999.3'
           ) THEN 1 ELSE 0
      END
    ) AS major_comp_flag
  FROM
    base b
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON b.hadm_id = dx.hadm_id
  GROUP BY
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime
),
-- 3. Compute scores, LOS, mortality, and assign quintile
scored AS (
  SELECT
    *,
    diagnosis_count + 20 * major_comp_flag AS score,
    CASE
      WHEN deathtime IS NOT NULL
           AND DATE_DIFF(deathtime, admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mort_30d_flag,
    DATE_DIFF(dischtime, admittime, DAY) AS los,
    NTILE(5) OVER (ORDER BY diagnosis_count + 20 * major_comp_flag) AS quintile
  FROM
    hadm_metrics
),
-- 4. Aggregate by quintile
agg AS (
  SELECT
    quintile,
    COUNT(*)                        AS n,
    ROUND(AVG(score), 2)            AS mean_score,
    ROUND(100 * AVG(mort_30d_flag), 1) AS pct_mort_30d,
    ROUND(100 * AVG(major_comp_flag), 1) AS pct_major_comp,
    -- median LOS among survivors
    -- use APPROX_QUANTILES over the LOS of survivors in each quintile
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_survivors
  FROM
    scored
  WHERE
    mort_30d_flag = 0
  GROUP BY
    quintile
)
SELECT
  *
FROM
  agg
ORDER BY
  quintile;