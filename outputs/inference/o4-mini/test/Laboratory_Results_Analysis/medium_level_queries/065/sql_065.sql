WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9  AND STARTS_WITH(d.icd_code, '410'))
      OR
      (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I21'))
    )
),
first_tn AS (
  SELECT
    le.hadm_id,
    le.valuenum AS initial_troponin
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
      ON le.itemid = di.itemid
    JOIN cohort_admissions AS c
      ON le.hadm_id = c.hadm_id
  WHERE
    LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),
filtered_cohort AS (
  SELECT
    hadm_id,
    initial_troponin
  FROM
    first_tn
  WHERE
    initial_troponin > 0.04
)
SELECT
  APPROX_QUANTILES(initial_troponin, 4)[OFFSET(1)] AS q1_troponin,
  APPROX_QUANTILES(initial_troponin, 4)[OFFSET(2)] AS median_troponin,
  APPROX_QUANTILES(initial_troponin, 4)[OFFSET(3)] AS q3_troponin
FROM
  filtered_cohort;