WITH ischemic_stroke_admissions AS (
  -- Get admissions for women age 40-50 with ischemic stroke
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      -- ICD-10 ischemic stroke
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'I63%' OR
        d.icd_code LIKE 'I65%' OR
        d.icd_code LIKE 'I66%'
      ))
      -- ICD-9 ischemic stroke
      OR (d.icd_version = 9 AND (
        d.icd_code LIKE '433%' OR
        d.icd_code LIKE '434%' OR
        d.icd_code = '436'
      ))
    )
  GROUP BY a.subject_id, a.hadm_id
),

icu_stays AS (
  -- Get ICU stays for the cohort, LOS 1-7 days
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.first_careunit,
    s.los,
    CASE
      WHEN s.los BETWEEN 1 AND 4 THEN '1-4'
      WHEN s.los BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
    JOIN ischemic_stroke_admissions a
      ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  WHERE
    s.los BETWEEN 1 AND 7
),

imaging_procedures AS (
  -- Get imaging procedures per admission
  SELECT
    pi.subject_id,
    pi.hadm_id,
    COUNT(*) AS imaging_proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
      ON pi.icd_code = dpi.icd_code AND pi.icd_version = dpi.icd_version
  WHERE
    (
      LOWER(dpi.long_title) LIKE '%ct%'
      OR LOWER(dpi.long_title) LIKE '%mri%'
      OR LOWER(dpi.long_title) LIKE '%radiology%'
      OR LOWER(dpi.long_title) LIKE '%ultrasound%'
      OR LOWER(dpi.long_title) LIKE '%imaging%'
      OR LOWER(dpi.long_title) LIKE '%x-ray%'
    )
  GROUP BY pi.subject_id, pi.hadm_id
),

admission_icu_imaging AS (
  -- Combine ICU stays and imaging procedure counts
  SELECT
    icu.first_careunit,
    icu.los_group,
    icu.hadm_id,
    COALESCE(img.imaging_proc_count, 0) AS imaging_proc_count
  FROM
    icu_stays icu
    LEFT JOIN imaging_procedures img
      ON icu.subject_id = img.subject_id AND icu.hadm_id = img.hadm_id
  WHERE
    icu.los_group IS NOT NULL
)

SELECT
  first_careunit AS icu,
  los_group,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  AVG(imaging_proc_count) AS mean_imaging_procs,
  MIN(imaging_proc_count) AS min_imaging_procs,
  MAX(imaging_proc_count) AS max_imaging_procs
FROM
  admission_icu_imaging
GROUP BY
  first_careunit,
  los_group
ORDER BY
  first_careunit,
  los_group;