WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE WHEN diag.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  -- cohort filters
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '5770')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
    )
),
imaging_counts AS (
  SELECT
    proc.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%ct%'
     OR LOWER(dproc.long_title) LIKE '%tomography%'
     OR LOWER(dproc.long_title) LIKE '%xray%'
     OR LOWER(dproc.long_title) LIKE '%radiography%'
  GROUP BY proc.hadm_id
),
cohort_with_imaging AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    CASE
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group,
    c.diagnosis_type,
    IFNULL(ic.imaging_count, 0) AS imaging_count
  FROM cohort c
  LEFT JOIN imaging_counts ic
    ON c.hadm_id = ic.hadm_id
  WHERE (c.los_days BETWEEN 1 AND 3 OR c.los_days BETWEEN 4 AND 7)
)
SELECT
  los_group,
  diagnosis_type,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(AVG(imaging_count),2) AS mean_imaging_per_admission
FROM cohort_with_imaging
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;