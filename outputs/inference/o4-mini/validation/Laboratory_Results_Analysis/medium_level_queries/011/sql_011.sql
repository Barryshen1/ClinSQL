WITH chest_pain_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
     AND a.subject_id = d.subject_id
  WHERE
    d.seq_num = 1
    AND d.icd_version = 9
    AND d.icd_code IN ('78650','78651','78652','78659')
),
male_61_71 AS (
  SELECT
    c.subject_id,
    c.hadm_id
  FROM
    chest_pain_adms c
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON c.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
),
first_tn AS (
  -- Find the first hs‐TnT draw time per admission
  SELECT
    le.subject_id,
    le.hadm_id,
    MIN(le.charttime) AS first_charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
      ON le.itemid = di.itemid
  WHERE
    (di.loinc_code = '6598-7'
     OR LOWER(di.label) LIKE '%troponin t%')
    AND le.valuenum IS NOT NULL
  GROUP BY
    le.subject_id,
    le.hadm_id
),
initial_hsTnT AS (
  -- Pull the first hs‐TnT value using the timestamp from first_tn
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM
    first_tn
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON le.subject_id = first_tn.subject_id
     AND le.hadm_id = first_tn.hadm_id
     AND le.charttime = first_tn.first_charttime
),
categorized AS (
  -- Restrict to our cohort and categorize their initial hs‐TnT
  SELECT
    m.hadm_id,
    CASE
      WHEN t.valuenum <= 14 THEN 'normal'
      WHEN t.valuenum > 14 AND t.valuenum <= 52 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category
  FROM
    male_61_71 m
    JOIN initial_hsTnT t
      ON m.subject_id = t.subject_id
     AND m.hadm_id = t.hadm_id
),
counts AS (
  SELECT
    category,
    COUNT(*) AS cnt
  FROM
    categorized
  GROUP BY
    category
),
total AS (
  SELECT
    COUNT(*) AS total_cnt
  FROM
    categorized
)
SELECT
  c.category,
  c.cnt,
  ROUND(100.0 * c.cnt / t.total_cnt, 2) AS percent
FROM
  counts c
  CROSS JOIN total t
ORDER BY
  c.category;