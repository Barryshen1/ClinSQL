WITH sepsis_primary AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.seq_num = 1
    AND (
      LOWER(d.long_title) LIKE '%sepsis%'
      OR LOWER(d.long_title) LIKE '%septic%'
      OR LOWER(d.long_title) LIKE '%septicemia%'
    )
    AND a.dischtime IS NOT NULL
),
aged_filtered AS (
  SELECT
    sp.*,
    (sp.anchor_age + (EXTRACT(YEAR FROM sp.admittime) - sp.anchor_year)) AS age_at_adm
  FROM
    sepsis_primary AS sp
)
SELECT
  STDDEV_POP(los_days) AS stddev_los_days
FROM (
  SELECT
    CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS FLOAT64) AS los_days
  FROM
    aged_filtered AS a
  WHERE
    a.age_at_adm BETWEEN 67 AND 77
    AND LOWER(a.gender) IN ('f','female')
) AS LOSSubset;