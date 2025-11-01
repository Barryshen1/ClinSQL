WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 86 AND 96
),

mcs_procedures AS (
  SELECT DISTINCT
    pe.hadm_id,
    pe.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
  ON
    pe.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%iabp%'
    OR LOWER(di.label) LIKE '%ecmo%'
    OR LOWER(di.label) LIKE '%ventricular assist%'
    OR LOWER(di.label) LIKE '%impella%'
    OR LOWER(di.label) LIKE '%mechanical circulatory support%'
),

mcs_count_per_hadm AS (
  SELECT
    pa.hadm_id,
    COUNT(DISTINCT mp.itemid) AS mcs_count
  FROM
    patient_admissions pa
  LEFT JOIN
    mcs_procedures mp
  ON
    pa.hadm_id = mp.hadm_id
  GROUP BY
    pa.hadm_id
),

percentiles AS (
  SELECT
    APPROX_QUANTILES(mcs_count, 1000)[OFFSET(250)] AS q1,
    APPROX_QUANTILES(mcs_count, 1000)[OFFSET(750)] AS q3
  FROM
    mcs_count_per_hadm
)

SELECT
  q3 - q1 AS iqr_mcs_procedures
FROM
  percentiles;