WITH cohort AS (
  -- Male inpatients aged 87-97
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),

lab_instability AS (
  -- Count critical lab events in first 72h of admission
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNTIF(
      (
        l.flag = 'abnormal'
        OR (SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL
            AND (
              (SAFE_CAST(l.ref_range_lower AS FLOAT64) IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64))
              OR
              (SAFE_CAST(l.ref_range_upper AS FLOAT64) IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64))
            )
        )
      )
    ) AS instability_score
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON c.hadm_id = l.hadm_id
      AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id
),

percentiles AS (
  -- Compute 95th percentile of instability score
  SELECT
    APPROX_QUANTILES(instability_score, 100)[95] AS p95_instability
  FROM
    lab_instability
),

p95_group AS (
  -- Admissions with instability_score >= P95
  SELECT
    li.subject_id,
    li.hadm_id,
    li.instability_score,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los
  FROM
    lab_instability li
    JOIN cohort c ON li.hadm_id = c.hadm_id
    CROSS JOIN percentiles p
  WHERE
    li.instability_score >= p.p95_instability
),

summary_p95 AS (
  SELECT
    COUNT(*) AS n_p95_admissions,
    AVG(los) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
    AVG(instability_score) AS mean_instability_score
  FROM
    p95_group
),

summary_all AS (
  -- For all inpatients (no age/gender filter)
  SELECT
    AVG(instability_score) AS mean_instability_score
  FROM (
    SELECT
      a.subject_id,
      a.hadm_id,
      COUNTIF(
        (
          l.flag = 'abnormal'
          OR (SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL
              AND (
                (SAFE_CAST(l.ref_range_lower AS FLOAT64) IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64))
                OR
                (SAFE_CAST(l.ref_range_upper AS FLOAT64) IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64))
              )
          )
        )
      ) AS instability_score
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON a.hadm_id = l.hadm_id
        AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    GROUP BY
      a.subject_id, a.hadm_id
  )
)

SELECT
  p.p95_instability AS instability_score_p95,
  s_p95.mean_los,
  s_p95.in_hospital_mortality_rate,
  s_p95.mean_instability_score AS mean_instability_score_p95_group,
  s_all.mean_instability_score AS mean_instability_score_all_inpatients
FROM
  percentiles p
  CROSS JOIN summary_p95 s_p95
  CROSS JOIN summary_all s_all
;