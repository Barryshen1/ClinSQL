WITH tia_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age >= 50 AND p.anchor_age <= 60
    AND (
      (di.icd_version = 9 AND di.icd_code = '4359') OR
      (di.icd_version = 10 AND di.icd_code = 'G459')
    )
),
admissions_with_los AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN tia_patients tp ON a.subject_id = tp.subject_id
  WHERE a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
imaging_codes AS (
  SELECT code AS hcpcs_cd
  FROM `physionet-data.mimiciv_3_1_hosp`.d_hcpcs
  WHERE code IN ('70450','70460','70470','70480','70490','70551','70552','70553','G0321')
     OR LOWER(short_description) LIKE '%computed tomography%'
     OR LOWER(short_description) LIKE '%magnetic resonance%'
),
admissions_with_imaging AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.los_days,
    COUNT(h.hcpcs_cd) AS procedure_count
  FROM admissions_with_los a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
    ON a.hadm_id = h.hadm_id
    AND h.hcpcs_cd IN (SELECT hcpcs_cd FROM imaging_codes)
  GROUP BY a.hadm_id, a.subject_id, a.los_days
),
los_groups AS (
  SELECT
    subject_id,
    hadm_id,
    procedure_count,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group
  FROM admissions_with_imaging
  WHERE los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(procedure_count) AS mean_procedures_per_admission
FROM los_groups
WHERE los_group IS NOT NULL
GROUP BY los_group
ORDER BY los_group;