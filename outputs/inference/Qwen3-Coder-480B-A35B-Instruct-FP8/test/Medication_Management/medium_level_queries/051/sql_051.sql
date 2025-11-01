WITH cohort AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        LOWER(dd.long_title) LIKE '%diabetes%'
        OR LOWER(dd.long_title) LIKE '%heart failure%'
      GROUP BY hadm_id
      HAVING COUNT(DISTINCT CASE
        WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1
        WHEN LOWER(dd.long_title) LIKE '%heart failure%' THEN 2
      END) = 2
    )
),

meds_classified AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.emar_id,
    e.charttime,
    CASE
      WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(e.medication) LIKE '%metformin%'
        OR LOWER(e.medication) LIKE '%glyburide%'
        OR LOWER(e.medication) LIKE '%glipizide%'
        OR LOWER(e.medication) LIKE '%glimepiride%'
        OR LOWER(e.medication) LIKE '%sitagliptin%'
        OR LOWER(e.medication) LIKE '%linagliptin%'
        OR LOWER(e.medication) LIKE '%pioglitazone%'
        OR LOWER(e.medication) LIKE '%empagliflozin%'
        OR LOWER(e.medication) LIKE '%dapagliflozin%' THEN 'Oral Agents'
      ELSE NULL
    END AS med_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN
    cohort c
  ON
    e.hadm_id = c.hadm_id
  WHERE
    e.charttime IS NOT NULL
    AND e.medication IS NOT NULL
),

meds_timed AS (
  SELECT
    m.*,
    c.stay_id,
    c.intime,
    c.outtime,
    CASE
      WHEN m.charttime BETWEEN c.intime AND c.intime + INTERVAL 12 HOUR THEN 'early'
      WHEN m.charttime BETWEEN c.outtime - INTERVAL 72 HOUR AND c.outtime THEN 'late'
      ELSE NULL
    END AS period
  FROM
    meds_classified m
  JOIN
    cohort c
  ON
    m.hadm_id = c.hadm_id
    AND m.charttime BETWEEN c.intime AND c.outtime
  WHERE
    m.med_class IN ('Insulin', 'Oral Agents')
),

stay_med_summary AS (
  SELECT
    stay_id,
    LOGICAL_OR(med_class = 'Insulin' AND period = 'early') AS early_insulin,
    LOGICAL_OR(med_class = 'Oral Agents' AND period = 'early') AS early_oral,
    LOGICAL_OR(med_class = 'Insulin' AND period = 'late') AS late_insulin,
    LOGICAL_OR(med_class = 'Oral Agents' AND period = 'late') AS late_oral
  FROM
    meds_timed
  GROUP BY
    stay_id
),

rates AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CAST(early_insulin AS INT64)) AS early_insulin_count,
    SUM(CAST(early_oral AS INT64)) AS early_oral_count,
    SUM(CAST(late_insulin AS INT64)) AS late_insulin_count,
    SUM(CAST(late_oral AS INT64)) AS late_oral_count
  FROM
    stay_med_summary
),

transitions AS (
  SELECT
    COUNT(*) AS total,
    SUM(CAST(CASE WHEN early_oral AND late_oral THEN 1 ELSE 0 END AS INT64)) AS oral_to_oral,
    SUM(CAST(CASE WHEN early_oral AND late_insulin THEN 1 ELSE 0 END AS INT64)) AS oral_to_insulin,
    SUM(CAST(CASE WHEN early_insulin AND late_oral THEN 1 ELSE 0 END AS INT64)) AS insulin_to_oral,
    SUM(CAST(CASE WHEN early_insulin AND late_insulin THEN 1 ELSE 0 END AS INT64)) AS insulin_to_insulin
  FROM
    stay_med_summary
)

SELECT
  'Early Insulin Rate (%)' AS metric,
  ROUND(100 * early_insulin_count / total_stays, 2) AS value
FROM
  rates

UNION ALL

SELECT
  'Early Oral Rate (%)' AS metric,
  ROUND(100 * early_oral_count / total_stays, 2) AS value
FROM
  rates

UNION ALL

SELECT
  'Late Insulin Rate (%)' AS metric,
  ROUND(100 * late_insulin_count / total_stays, 2) AS value
FROM
  rates

UNION ALL

SELECT
  'Late Oral Rate (%)' AS metric,
  ROUND(100 * late_oral_count / total_stays, 2) AS value
FROM
  rates

UNION ALL

SELECT
  'Oral → Oral (%)' AS metric,
  ROUND(100 * oral_to_oral / total, 2) AS value
FROM
  transitions

UNION ALL

SELECT
  'Oral → Insulin (%)' AS metric,
  ROUND(100 * oral_to_insulin / total, 2) AS value
FROM
  transitions

UNION ALL

SELECT
  'Insulin → Oral (%)' AS metric,
  ROUND(100 * insulin_to_oral / total, 2) AS value
FROM
  transitions

UNION ALL

SELECT
  'Insulin → Insulin (%)' AS metric,
  ROUND(100 * insulin_to_insulin / total, 2) AS value
FROM
  transitions;