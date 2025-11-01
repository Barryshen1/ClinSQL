WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    -- approximate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 47 AND 57
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5770','5771')) OR
      (d.icd_version = 10 AND d.icd_code IN ('K850','K851','K852','K853','K858','K859'))
    )
),
ct_mri_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    CASE
      WHEN c.los_days BETWEEN 1 AND 4 THEN 'LOS 1-4 days'
      WHEN c.los_days BETWEEN 5 AND 8 THEN 'LOS 5-8 days'
    END AS los_group,
    COUNT(proc.icd_code) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON c.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE c.los_days BETWEEN 1 AND 8
    AND (
      dp.long_title LIKE '%CT%' OR
      dp.long_title LIKE '%MRI%'
    )
  GROUP BY c.subject_id, c.hadm_id, c.los_days, los_group
)
SELECT
  los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(procedure_count) AS mean_ct_mri_per_admission
FROM ct_mri_counts
GROUP BY los_group
ORDER BY los_group;