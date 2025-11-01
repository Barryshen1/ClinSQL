WITH male_senior_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
imaging_procs AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code,
    pi.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
    ON pi.icd_code = dpi.icd_code
    AND pi.icd_version = dpi.icd_version
  WHERE
    LOWER(dpi.long_title) LIKE '%x-ray%'
    OR LOWER(dpi.long_title) LIKE '%radiograph%'
    OR LOWER(dpi.long_title) LIKE '%imaging%'
    OR LOWER(dpi.long_title) LIKE '%ct%'
    OR LOWER(dpi.long_title) LIKE '%mri%'
    OR LOWER(dpi.long_title) LIKE '%ultrasound%'
),
counts_per_admission AS (
  SELECT
    msp.subject_id,
    msp.hadm_id,
    msp.los_days,
    COUNT(*) AS imaging_proc_count
  FROM
    male_senior_patients msp
  LEFT JOIN
    imaging_procs ip
    ON msp.subject_id = ip.subject_id
    AND msp.hadm_id = ip.hadm_id
  WHERE
    msp.los_days BETWEEN 1 AND 7
  GROUP BY
    msp.subject_id, msp.hadm_id, msp.los_days
),
los_grouped AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    imaging_proc_count
  FROM
    counts_per_admission
)
SELECT
  los_group,
  AVG(imaging_proc_count) AS mean_proc_count,
  MIN(imaging_proc_count) AS min_proc_count,
  MAX(imaging_proc_count) AS max_proc_count
FROM
  los_grouped
GROUP BY
  los_group
ORDER BY
  los_group;