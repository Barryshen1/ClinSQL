WITH sepsis_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + DATE_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) = 76
    AND (
      LOWER(dd.long_title) LIKE '%sepsis%'
      OR LOWER(dd.long_title) LIKE '%septic%'
    )
),

platelet_itemid AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) = 'platelets'
),

platelet_labs AS (
  SELECT
    l.hadm_id,
    l.valuenum
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    sepsis_cohort c
    ON l.hadm_id = c.hadm_id
  JOIN
    platelet_itemid p
    ON l.itemid = p.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),

avg_platelets_per_patient AS (
  SELECT
    hadm_id,
    AVG(valuenum) AS avg_platelet_count
  FROM
    platelet_labs
  GROUP BY
    hadm_id
)

SELECT
  APPROX_QUANTILES(avg_platelet_count, 2)[OFFSET(1)] AS median_platelet_count
FROM
  avg_platelets_per_patient;