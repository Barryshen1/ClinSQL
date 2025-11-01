WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 24
),

diabetes_hf AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON c.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (dd.icd_code LIKE 'E11%' OR dd.long_title LIKE '%Type 2 diabetes%')
    AND (dd.icd_code LIKE 'I50%' OR dd.long_title LIKE '%Heart failure%')
),

meds_first_24h AS (
  SELECT DISTINCT
    dh.subject_id,
    CASE WHEN LOWER(e.medication) LIKE '%insulin%' THEN 1 ELSE 0 END AS insulin_first,
    CASE WHEN LOWER(e.medication) NOT LIKE '%insulin%' AND e.medication IS NOT NULL THEN 1 ELSE 0 END AS oral_first
  FROM
    diabetes_hf dh
  JOIN
    cohort c
    ON dh.hadm_id = c.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.emar e
    ON dh.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 1 DAY)
),

meds_last_24h AS (
  SELECT DISTINCT
    dh.subject_id,
    CASE WHEN LOWER(e.medication) LIKE '%insulin%' THEN 1 ELSE 0 END AS insulin_last,
    CASE WHEN LOWER(e.medication) NOT LIKE '%insulin%' AND e.medication IS NOT NULL THEN 1 ELSE 0 END AS oral_last
  FROM
    diabetes_hf dh
  JOIN
    cohort c
    ON dh.hadm_id = c.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.emar e
    ON dh.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 1 DAY) AND c.dischtime
),

first_agg AS (
  SELECT
    subject_id,
    MAX(insulin_first) AS insulin_first,
    MAX(oral_first) AS oral_first
  FROM meds_first_24h
  GROUP BY subject_id
),

last_agg AS (
  SELECT
    subject_id,
    MAX(insulin_last) AS insulin_last,
    MAX(oral_last) AS oral_last
  FROM meds_last_24h
  GROUP BY subject_id
),

combined AS (
  SELECT
    dh.subject_id,
    COALESCE(f.insulin_first, 0) AS insulin_first,
    COALESCE(f.oral_first, 0) AS oral_first,
    COALESCE(l.insulin_last, 0) AS insulin_last,
    COALESCE(l.oral_last, 0) AS oral_last
  FROM
    diabetes_hf dh
  LEFT JOIN
    first_agg f ON dh.subject_id = f.subject_id
  LEFT JOIN
    last_agg l ON dh.subject_id = l.subject_id
)

SELECT
  ROUND(AVG(insulin_first) * 100, 2) AS insulin_first_24h_pct,
  ROUND(AVG(insulin_last) * 100, 2) AS insulin_last_24h_pct,
  ROUND((AVG(insulin_last) - AVG(insulin_first)) * 100, 2) AS insulin_net_change_pp,
  ROUND(AVG(oral_first) * 100, 2) AS oral_first_24h_pct,
  ROUND(AVG(oral_last) * 100, 2) AS oral_last_24h_pct,
  ROUND((AVG(oral_last) - AVG(oral_first)) * 100, 2) AS oral_net_change_pp
FROM
  combined;