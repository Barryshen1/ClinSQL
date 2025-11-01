WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.subject_id = dx.subject_id AND a.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND LOWER(d_dx.long_title) LIKE '%hyperosmolar%'
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
proc_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los,
    COUNT(proc.icd_code) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON c.subject_id = proc.subject_id AND c.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE d_proc.icd_code IS NULL
        OR LOWER(d_proc.long_title) LIKE '%radiograph%'
        OR LOWER(d_proc.long_title) LIKE '%x-ray%'
        OR LOWER(d_proc.long_title) LIKE '%computed tomography%'
        OR LOWER(d_proc.long_title) LIKE '%ct scan%'
  GROUP BY c.subject_id, c.hadm_id, c.los
),
grouped AS (
  SELECT
    CASE
      WHEN los BETWEEN 1 AND 4 THEN 'LOS_1_4'
      WHEN los BETWEEN 5 AND 7 THEN 'LOS_5_7'
    END AS los_group,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(proc_count) AS mean_proc_per_admission
  FROM proc_counts
  GROUP BY los_group
)
SELECT *
FROM grouped
ORDER BY los_group;