WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
),
radiology_procs AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    COUNT(*) AS num_radiology_procs
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
      ON pr.icd_code = dpr.icd_code
      AND pr.icd_version = dpr.icd_version
  WHERE
    LOWER(dpr.long_title) LIKE '%radiology%'
    OR LOWER(dpr.long_title) LIKE '%radiography%'
    OR LOWER(dpr.long_title) LIKE '%x-ray%'
    OR LOWER(dpr.long_title) LIKE '%ct%'
    OR LOWER(dpr.long_title) LIKE '%computed tomography%'
  GROUP BY
    pr.subject_id, pr.hadm_id
),
admission_radiology AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los,
    COALESCE(r.num_radiology_procs, 0) AS num_radiology_procs,
    CASE
      WHEN c.los BETWEEN 1 AND 4 THEN 'LOS 1-4 days'
      WHEN c.los BETWEEN 5 AND 7 THEN 'LOS 5-7 days'
      ELSE NULL
    END AS los_group
  FROM
    cohort c
    LEFT JOIN radiology_procs r
      ON c.subject_id = r.subject_id
      AND c.hadm_id = r.hadm_id
  WHERE
    c.los BETWEEN 1 AND 7
    AND (
      c.los BETWEEN 1 AND 4
      OR c.los BETWEEN 5 AND 7
    )
)
SELECT
  los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(hadm_id) AS admission_count,
  ROUND(AVG(num_radiology_procs), 2) AS mean_radiology_ct_procs_per_admission
FROM
  admission_radiology
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group
ORDER BY
  los_group;