WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = a.subject_id
        AND diag.hadm_id = a.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code = '5770') 
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
        )
    )
),

cohort_with_los AS (
  SELECT
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM cohort
  WHERE 
    age_at_admission BETWEEN 47 AND 57
    AND DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 8
),

ct_mri_procedures AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    d.long_title LIKE '%computed tomography%'
    OR d.long_title LIKE '%CT%'
    OR d.long_title LIKE '%magnetic resonance%'
    OR d.long_title LIKE '%MRI%'
  GROUP BY p.hadm_id
)

SELECT
  c.los_group,
  COUNT(c.hadm_id) AS admission_count,
  AVG(COALESCE(p.procedure_count, 0)) AS mean_procedures_per_admission
FROM cohort_with_los c
LEFT JOIN ct_mri_procedures p
  ON c.hadm_id = p.hadm_id
WHERE c.los_group IS NOT NULL
GROUP BY c.los_group
ORDER BY c.los_group;