WITH eligible_adms AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) BETWEEN 47 AND 57
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '577.0')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
    )
),
ctmri_procs AS (
  SELECT
    proc.hadm_id,
    COUNT(*) AS num_ctmri
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%ct%'
     OR LOWER(dproc.long_title) LIKE '%computed tomography%'
     OR LOWER(dproc.long_title) LIKE '%mri%'
     OR LOWER(dproc.long_title) LIKE '%magnetic resonance%'
  GROUP BY proc.hadm_id
)
SELECT
  CASE
    WHEN ea.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN ea.los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_group,
  COUNT(DISTINCT ea.subject_id) AS patient_counts,
  AVG(COALESCE(cp.num_ctmri, 0)) AS mean_ctmri_procedures_per_admission
FROM eligible_adms ea
LEFT JOIN ctmri_procs cp
  ON ea.hadm_id = cp.hadm_id
WHERE ea.los_days BETWEEN 1 AND 8
GROUP BY los_group
ORDER BY los_group;