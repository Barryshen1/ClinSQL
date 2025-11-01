WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
imaging_procs AS (
  SELECT
    pi.hadm_id,
    COUNT(*) AS imaging_proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
      ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE
    -- Imaging procedures: filter by keywords in long_title
    LOWER(dip.long_title) LIKE '%x-ray%'
    OR LOWER(dip.long_title) LIKE '%ct%'
    OR LOWER(dip.long_title) LIKE '%mri%'
    OR LOWER(dip.long_title) LIKE '%ultrasound%'
    OR LOWER(dip.long_title) LIKE '%radiography%'
    OR LOWER(dip.long_title) LIKE '%imaging%'
    OR LOWER(dip.long_title) LIKE '%scan%'
    OR LOWER(dip.long_title) LIKE '%nuclear medicine%'
    OR LOWER(dip.long_title) LIKE '%fluoroscopy%'
    OR LOWER(dip.long_title) LIKE '%pet%'
  GROUP BY
    pi.hadm_id
),
admission_imaging AS (
  SELECT
    c.hadm_id,
    c.los_days,
    CASE
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group,
    IFNULL(ip.imaging_proc_count, 0) AS imaging_proc_count
  FROM
    cohort c
    LEFT JOIN imaging_procs ip
      ON c.hadm_id = ip.hadm_id
  WHERE
    c.los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  COUNT(*) AS num_admissions,
  AVG(imaging_proc_count) AS mean_imaging_procs,
  MIN(imaging_proc_count) AS min_imaging_procs,
  MAX(imaging_proc_count) AS max_imaging_procs
FROM
  admission_imaging
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group
ORDER BY
  los_group;