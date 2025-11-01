WITH asthma_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(di.long_title) LIKE '%asthma%'
),
filtered_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group
  FROM
    asthma_admissions
  WHERE
    los_days BETWEEN 1 AND 7
),
procedures_per_admission AS (
  SELECT
    fa.los_group,
    fa.subject_id,
    fa.hadm_id,
    COUNT(pi.icd_code) AS proc_count
  FROM
    filtered_admissions AS fa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
      ON fa.subject_id = pi.subject_id
      AND fa.hadm_id = pi.hadm_id
  GROUP BY
    fa.los_group,
    fa.subject_id,
    fa.hadm_id
)
SELECT
  los_group,
  -- APPROX_QUANTILES(..., 4) returns 5 values: 0th,25th,50th,75th,100th percentiles
  APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS p75
FROM
  procedures_per_admission
GROUP BY
  los_group
ORDER BY
  los_group;