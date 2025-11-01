WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    -- Trauma: ICD codes in 800-959 prefix
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS INT64) BETWEEN 800 AND 959
    )
),

-- 2) First-24h medication complexity (distinct medications started within 24h)
cohort_meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT ph.medication) AS complexity
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph
    ON ph.subject_id = c.subject_id
   AND ph.hadm_id = c.hadm_id
   AND ph.starttime >= c.admittime
   AND ph.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
),

-- 3) Per-patient metrics: quartile assignment, percentile, LOS
metrics AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag AS mortality,
    m.complexity,
    NTILE(4) OVER (ORDER BY m.complexity) AS quartile,
    (PERCENT_RANK() OVER (ORDER BY m.complexity) * 100) AS percentile,
    TIMESTAMP_DIFF(m.dischtime, m.admittime, SECOND) / 86400.0 AS los_days
  FROM cohort_meds AS m
  -- Note: if there are rows with null admittime/dischtime, they are excluded by the join above
),

-- 4) Serotonergic exposure within first 24h (for risk)
serotonergic_exposure AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    SUM(
      CASE
        WHEN LOWER(p.medication) LIKE '%sertraline%'           OR
             LOWER(p.medication) LIKE '%fluoxetine%'           OR
             LOWER(p.medication) LIKE '%paroxetine%'           OR
             LOWER(p.medication) LIKE '%citalopram%'           OR
             LOWER(p.medication) LIKE '%escitalopram%'        OR
             LOWER(p.medication) LIKE '%venlafaxine%'          OR
             LOWER(p.medication) LIKE '%duloxetine%'          OR
             LOWER(p.medication) LIKE '%mirtazapine%'          OR
             LOWER(p.medication) LIKE '%amitriptyline%'        OR
             LOWER(p.medication) LIKE '%nortriptyline%'        OR
             LOWER(p.medication) LIKE '%trazodone%'            OR
             LOWER(p.medication) LIKE '%sumatriptan%'          OR
             LOWER(p.medication) LIKE '%rizatriptan%'          OR
             LOWER(p.medication) LIKE '%linezolid%'            OR
             LOWER(p.medication) LIKE '%triptan%'
        THEN 1 ELSE 0
      END
    ) AS serotonergic_exposures
  FROM cohort AS s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` AS p
    ON p.subject_id = s.subject_id
   AND p.hadm_id = s.hadm_id
   AND p.starttime >= s.admittime
   AND p.starttime < TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
  GROUP BY s.subject_id, s.hadm_id
),

serotonergic_risk AS (
  SELECT
    subject_id,
    hadm_id,
    CASE WHEN serotonergic_exposures >= 2 THEN 1 ELSE 0 END AS serotonergic_risk
  FROM serotonergic_exposure
)

-- 5) Final per-patient results plus group-level aggregates via window functions
SELECT
  mu.subject_id,
  mu.hadm_id,
  mu.admittime,
  mu.dischtime,
  mu.los_days,
  mu.mortality,
  mu.complexity AS first24h_med_complexity,
  mu.percentile AS complexity_percentile,
  CASE
    WHEN mu.complexity <= qt.q1 THEN 1
    WHEN mu.complexity <= qt.q2 THEN 2
    WHEN mu.complexity <= qt.q3 THEN 3
    ELSE 4
  END AS quartile,
  COALESCE(sr.serotonergic_risk, 0) AS serotonergic_risk,
  -- Average metrics by serotonergic risk (group-level context)
  AVG(mu.percentile) OVER (PARTITION BY COALESCE(sr.serotonergic_risk, 0)) AS avg_percentile_by_risk,
  AVG(mu.los_days) OVER (PARTITION BY COALESCE(sr.serotonergic_risk, 0)) AS avg_los_by_risk,
  AVG(mu.mortality) OVER (PARTITION BY COALESCE(sr.serotonergic_risk, 0)) AS mortality_rate_by_risk,
  -- Average LOS and mortality by quartile (top-quartile emphasis possible)
  AVG(mu.los_days) OVER (PARTITION BY mu.quartile) AS avg_los_by_quartile,
  AVG(mu.mortality) OVER (PARTITION BY mu.quartile) AS mortality_rate_by_quartile
FROM metrics AS mu
LEFT JOIN serotonergic_risk sr
  ON mu.subject_id = sr.subject_id AND mu.hadm_id = sr.hadm_id
CROSS JOIN (
  -- Quartile thresholds derived from the cohort
  SELECT quantiles[OFFSET(1)] AS q1,
         quantiles[OFFSET(2)] AS q2,
         quantiles[OFFSET(3)] AS q3,
         quantiles[OFFSET(4)] AS q4
  FROM (
    SELECT APPROX_QUANTILES(complexity, 4) AS quantiles
    FROM cohort_meds
  )
) AS qt
ORDER BY mu.subject_id, mu.hadm_id;