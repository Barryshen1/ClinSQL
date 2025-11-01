WITH target_population AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.deathtime IS NOT NULL AND DATETIME_DIFF(a.deathtime, a.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

dkas AS (
  SELECT DISTINCT
    tp.*
  FROM
    target_population tp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    tp.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    (d.icd_code IN ('2501', 'E101', 'E111') AND d.icd_version IN (9, 10))
),

complications AS (
  SELECT
    tp.hadm_id,
    MAX(CASE
      WHEN d.icd_code BETWEEN '410' AND '414'
        OR d.icd_code BETWEEN '420' AND '429'
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I[0-9]+'))
      THEN 1
      ELSE 0
    END) AS cardiovascular_complication,
    MAX(CASE
      WHEN d.icd_code BETWEEN '340' AND '349'
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^G[0-9]+'))
      THEN 1
      ELSE 0
    END) AS neurologic_complication
  FROM
    target_population tp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    tp.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  GROUP BY
    tp.hadm_id
),

dkas_with_comps AS (
  SELECT
    d.*,
    COALESCE(c.cardiovascular_complication, 0) AS cardiovascular_complication,
    COALESCE(c.neurologic_complication, 0) AS neurologic_complication
  FROM
    dkas d
  LEFT JOIN
    complications c
  ON
    d.hadm_id = c.hadm_id
),

all_with_comps AS (
  SELECT
    tp.*,
    COALESCE(c.cardiovascular_complication, 0) AS cardiovascular_complication,
    COALESCE(c.neurologic_complication, 0) AS neurologic_complication
  FROM
    target_population tp
  LEFT JOIN
    complications c
  ON
    tp.hadm_id = c.hadm_id
),

dkas_stats AS (
  SELECT
    'DKA' AS cohort,
    AVG(hospital_expire_flag) AS mean_risk_score,
    AVG(mortality_30d) AS mortality_30d_rate,
    AVG(cardiovascular_complication) AS cardio_comp_rate,
    AVG(neurologic_complication) AS neuro_comp_rate,
    AVG(CASE WHEN deathtime IS NULL THEN los_days ELSE NULL END) AS mean_survivor_los
  FROM
    dkas_with_comps
),

all_stats AS (
  SELECT
    'All Males 39-49' AS cohort,
    AVG(hospital_expire_flag) AS mean_risk_score,
    AVG(mortality_30d) AS mortality_30d_rate,
    AVG(cardiovascular_complication) AS cardio_comp_rate,
    AVG(neurologic_complication) AS neuro_comp_rate,
    AVG(CASE WHEN deathtime IS NULL THEN los_days ELSE NULL END) AS mean_survivor_los
  FROM
    all_with_comps
),

combined_stats AS (
  SELECT * FROM dkas_stats
  UNION ALL
  SELECT * FROM all_stats
),

risk_percentile AS (
  SELECT
    PERCENTILE_CONT(hospital_expire_flag, 0.5) OVER () AS median_risk,
    PERCENTILE_CONT(hospital_expire_flag, 0.95) OVER () AS p95_risk
  FROM
    all_with_comps
  LIMIT 1
)

SELECT
  cs.*,
  rp.median_risk,
  rp.p95_risk
FROM
  combined_stats cs
CROSS JOIN
  risk_percentile rp
ORDER BY
  cs.cohort;