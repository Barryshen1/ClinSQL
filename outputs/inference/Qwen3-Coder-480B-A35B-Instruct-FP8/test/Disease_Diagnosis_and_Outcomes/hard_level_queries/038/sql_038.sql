WITH cohort_base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),

aki_cohort AS (
  SELECT DISTINCT
    cb.*
  FROM
    cohort_base cb
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    cb.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code = '5849')
    OR (d.icd_version = 10 AND d.icd_code = 'N179')
),

creatinine_max AS (
  SELECT
    l.hadm_id,
    MAX(l.valuenum) AS max_creatinine
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%creatinine%'
    AND l.valuenum IS NOT NULL
  GROUP BY
    l.hadm_id
),

aki_with_creatinine AS (
  SELECT
    a.*,
    c.max_creatinine
  FROM
    aki_cohort a
  LEFT JOIN
    creatinine_max c
  ON
    a.hadm_id = c.hadm_id
),

general_creatinine AS (
  SELECT
    cb.hadm_id,
    MAX(l.valuenum) AS max_creatinine
  FROM
    cohort_base cb
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    cb.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%creatinine%'
    AND l.valuenum IS NOT NULL
  GROUP BY
    cb.hadm_id
),

aki_ards AS (
  SELECT DISTINCT
    a.hadm_id
  FROM
    aki_with_creatinine a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code = '5185')
    OR (d.icd_version = 10 AND d.icd_code = 'J80')
),

aki_stats AS (
  SELECT
    APPROX_QUANTILES(max_creatinine, 100)[OFFSET(50)] AS median_creatinine,
    APPROX_QUANTILES(max_creatinine, 100)[OFFSET(25)] AS q1_creatinine,
    APPROX_QUANTILES(max_creatinine, 100)[OFFSET(75)] AS q3_creatinine,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_30d,
    AVG(CASE WHEN los_days IS NOT NULL AND hospital_expire_flag = 0 THEN los_days ELSE NULL END) AS mean_survivor_los,
    COUNT(*) AS total_aki,
    COUNT(ards.hadm_id) AS ards_count
  FROM
    aki_with_creatinine aki
  LEFT JOIN
    aki_ards ards
  ON
    aki.hadm_id = ards.hadm_id
),

general_stats AS (
  SELECT
    APPROX_QUANTILES(max_creatinine, 100) AS creatinine_percentiles
  FROM
    general_creatinine
),

aki_median_scalar AS (
  SELECT APPROX_QUANTILES(max_creatinine, 100)[OFFSET(50)] AS aki_median
  FROM aki_with_creatinine
),

percentile_lookup AS (
  SELECT
    aki_median,
    creatinine_percentiles
  FROM
    aki_median_scalar
  CROSS JOIN
    general_stats
)

SELECT
  aki_stats.median_creatinine,
  aki_stats.q1_creatinine,
  aki_stats.q3_creatinine,
  aki_stats.mortality_30d,
  aki_stats.ards_count,
  aki_stats.total_aki,
  SAFE_DIVIDE(aki_stats.ards_count, aki_stats.total_aki) AS ards_rate,
  aki_stats.mean_survivor_los,
  (
    SELECT
      i
    FROM
      UNNEST(ARRAY(SELECT AS STRUCT GENERATE_ARRAY(1, 100) AS idx)) AS arr,
      UNNEST(arr.idx) AS i
    WHERE
      pl.creatinine_percentiles[ORDINAL(i)] >= pl.aki_median
    ORDER BY
      i
    LIMIT 1
  ) AS risk_percentile
FROM
  aki_stats
CROSS JOIN
  percentile_lookup pl
LIMIT 1;