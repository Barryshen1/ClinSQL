WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
hhs_admissions AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.los_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%hyperosmolar%'
    AND LOWER(d.long_title) LIKE '%diabetes%'
    -- More specific: HHS codes
    -- E11.01, E13.01, etc. But text search is safer if coding varies.
    -- Alternatively, we can use known codes: E11.01, E13.01, E14.01
    -- But the question says "HHS", so we rely on diagnosis including HHS or hyperosmolar hyperglycemic
    OR (di.icd_code IN ('E1101', 'E1301', 'E1401') AND di.icd_version = 10)
    OR (di.icd_code = '251.2' AND di.icd_version = 9) -- older ICD-9 code for HHS
),
radiology_procedures AS (
  SELECT
    h.hadm_id,
    h.los_days,
    COUNT(*) AS proc_count
  FROM hhs_admissions h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
    ON h.hadm_id = pi.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ct%'
    OR LOWER(d.long_title) LIKE '%computed tomography%'
    OR LOWER(d.long_title) LIKE '%radiograph%'
    OR LOWER(d.long_title) LIKE '%x-ray%'
    OR LOWER(d.long_title) LIKE '%roentgen%'
  GROUP BY h.hadm_id, h.los_days
),
los_groups AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM hhs_admissions
  WHERE los_days BETWEEN 1 AND 7
),
summary AS (
  SELECT
    lg.los_group,
    COUNT(DISTINCT lg.subject_id) AS patient_count,
    COUNT(lg.hadm_id) AS admission_count,
    AVG(COALESCE(rp.proc_count, 0)) AS mean_radiology_procedures_per_admission
  FROM los_groups lg
  LEFT JOIN radiology_procedures rp
    ON lg.hadm_id = rp.hadm_id
  GROUP BY lg.los_group
)
SELECT
  los_group,
  patient_count,
  admission_count,
  mean_radiology_procedures_per_admission
FROM summary
ORDER BY los_group;