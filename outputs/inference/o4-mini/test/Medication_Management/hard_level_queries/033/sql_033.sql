WITH sepsis_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(dd.long_title) LIKE '%sepsis%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
),

med_complexity AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    -- count distinct drug + dose unit + route as the complexity score
    COUNT(DISTINCT CONCAT(pr.drug, '||', pr.dose_unit_rx, '||', pr.route)) AS complexity,
    -- flag for any QT-prolonging drugs
    MAX(CASE
      WHEN LOWER(pr.drug) IN (
        'amiodarone','haloperidol','azithromycin','levofloxacin','ciprofloxacin'
      ) THEN 1
      ELSE 0
    END) AS qt_rx,
    -- flag for any bleeding-risk drugs
    MAX(CASE
      WHEN LOWER(pr.drug) IN (
        'warfarin','heparin','enoxaparin','apixaban','rivaroxaban'
      ) THEN 1
      ELSE 0
    END) AS bleed_rx
  FROM
    sepsis_cohort AS s
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON s.hadm_id = pr.hadm_id
  WHERE
    pr.starttime BETWEEN s.admittime
      AND TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
  GROUP BY
    s.subject_id,
    s.hadm_id
),

complexity_with_groups AS (
  SELECT
    mc.*,
    CASE
      WHEN mc.qt_rx = 1
       AND mc.bleed_rx = 1 THEN 1
      ELSE 0
    END AS group_flag
  FROM
    med_complexity AS mc
),

pct_ranked AS (
  SELECT
    subject_id,
    hadm_id,
    complexity,
    group_flag,
    PERCENT_RANK() OVER (
      PARTITION BY group_flag
      ORDER BY complexity
    ) AS pct_rank
  FROM
    complexity_with_groups
),

-- compute the 75th percentile of complexity among all sepsis patients
quantile_75 AS (
  SELECT
    APPROX_QUANTILES(complexity, 100)[OFFSET(75)] AS threshold_75
  FROM
    complexity_with_groups
),

top_quartile AS (
  SELECT
    cwg.subject_id,
    cwg.hadm_id,
    cwg.complexity,
    s.dischtime,
    s.admittime,
    s.hospital_expire_flag,
    DATE_DIFF(s.dischtime, s.admittime, DAY) AS los_days
  FROM
    complexity_with_groups AS cwg
    CROSS JOIN quantile_75 AS q
    JOIN sepsis_cohort AS s
      ON cwg.hadm_id = s.hadm_id
  WHERE
    cwg.complexity >= q.threshold_75
)

-- Final outputs:  
-- 1) Distribution & percentile ranks by group  
-- 2) LOS & mortality for top quartile
SELECT
  'complexity_distribution' AS report,
  pct.subject_id,
  pct.hadm_id,
  pct.complexity,
  pct.group_flag,
  pct.pct_rank
FROM
  pct_ranked AS pct

UNION ALL

SELECT
  'top_quartile_los_mortality' AS report,
  tq.subject_id,
  tq.hadm_id,
  tq.los_days AS complexity,         -- reuse the column for LOS
  tq.hospital_expire_flag AS group_flag,  -- reuse for mortality flag
  NULL AS pct_rank
FROM
  top_quartile AS tq
ORDER BY
  report,
  subject_id,
  hadm_id;