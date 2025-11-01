WITH patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATETIME_ADD(DATETIME(p.anchor_year, 1, 1, 0, 0, 0), INTERVAL p.anchor_age YEAR) AS anchor_datetime,
    -- Compute age at admission
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
),
filtered_patients AS (
  SELECT
    pa.subject_id
  FROM
    patient_age pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pa.subject_id = di.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
  ON
    di.icd_code = d_diag.icd_code AND di.icd_version = d_diag.icd_version
  WHERE
    pa.gender = 'M'
    AND pa.age_at_admit BETWEEN 90 AND 100
    AND LOWER(d_diag.long_title) LIKE '%transient ischemic%'
),
admission_los AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN
    filtered_patients fp
  ON
    a.subject_id = fp.subject_id
  WHERE
    a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
imaging_procedures AS (
  SELECT
    pi.hadm_id,
    COUNT(*) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d_proc
  ON
    pi.icd_code = d_proc.icd_code AND pi.icd_version = d_proc.icd_version
  WHERE
    LOWER(d_proc.long_title) LIKE '%imaging%'
    OR LOWER(d_proc.long_title) LIKE '%ct%'
    OR LOWER(d_proc.long_title) LIKE '%mri%'
    OR LOWER(d_proc.long_title) LIKE '%computed tomography%'
    OR LOWER(d_proc.long_title) LIKE '%magnetic resonance%'
    OR LOWER(d_proc.long_title) LIKE '%angiography%'
    OR LOWER(d_proc.long_title) LIKE '%scan%'
    OR LOWER(d_proc.long_title) LIKE '%ultrasound%'
    OR LOWER(d_proc.long_title) LIKE '%echo%'
  GROUP BY
    pi.hadm_id
),
admission_with_imaging AS (
  SELECT
    al.hadm_id,
    al.los_days,
    COALESCE(ip.proc_count, 0) AS proc_count
  FROM
    admission_los al
  LEFT JOIN
    imaging_procedures ip
  ON
    al.hadm_id = ip.hadm_id
),
los_groups AS (
  SELECT
    hadm_id,
    proc_count,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group
  FROM
    admission_with_imaging
  WHERE
    los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  AVG(proc_count) AS mean_procedures_per_admission,
  MIN(proc_count) AS min_procedures_per_admission,
  MAX(proc_count) AS max_procedures_per_admission
FROM
  los_groups
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group
ORDER BY
  los_group;