WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%' OR d.icd_code = '4111')
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I2[0-5]'))
    )
),

first_trop AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    d.label = 'Troponin I'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
)

SELECT
  COUNT(*) AS patient_count,
  AVG(f.valuenum) AS mean_trop,
  APPROX_QUANTILES(f.valuenum, 4)[OFFSET(2)] AS median_trop,
  APPROX_QUANTILES(f.valuenum, 4)[OFFSET(1)] AS q1_trop,
  APPROX_QUANTILES(f.valuenum, 4)[OFFSET(3)] AS q3_trop
FROM
  cohort c
JOIN
  first_trop f
ON
  c.hadm_id = f.hadm_id
WHERE
  f.rn = 1
  AND f.valuenum > 0.04;