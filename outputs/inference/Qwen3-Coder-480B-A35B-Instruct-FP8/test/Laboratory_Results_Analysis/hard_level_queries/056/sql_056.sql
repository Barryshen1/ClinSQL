WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    i.los AS icu_los,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
),

lab_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(*) AS lab_instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  WHERE
    le.charttime >= c.intime
    AND le.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND (
      le.flag = 'abnormal'
      OR (
        le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
      )
    )
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

percentile_95 AS (
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.95) OVER() AS p95_score
  FROM
    lab_scores
  LIMIT 1
),

top_tier AS (
  SELECT
    ls.*,
    c.icu_los,
    c.hospital_expire_flag
  FROM
    lab_scores ls
  JOIN
    cohort c
    ON ls.stay_id = c.stay_id
  CROSS JOIN
    percentile_95 p
  WHERE
    ls.lab_instability_score >= p.p95_score
),

general_stats AS (
  SELECT
    AVG(icu_los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(CASE WHEN lab_instability_score > 0 THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM
    cohort c
  LEFT JOIN
    lab_scores ls
    ON c.stay_id = ls.stay_id
),

top_tier_stats AS (
  SELECT
    AVG(icu_los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(CASE WHEN lab_instability_score > 0 THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM
    top_tier
)

SELECT
  'Top 5% (95th percentile and above)' AS group_name,
  t.avg_los,
  t.mortality_rate,
  t.critical_lab_rate
FROM
  top_tier_stats t

UNION ALL

SELECT
  'General inpatients' AS group_name,
  g.avg_los,
  g.mortality_rate,
  g.critical_lab_rate
FROM
  general_stats g;