WITH pancreatitis_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND did.icd_version = 10
    AND LOWER(did.long_title) LIKE '%acute pancreatitis%'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND EXTRACT(DAY FROM (a.dischtime - a.admittime)) BETWEEN 1 AND 8
),
ct_mri_procedures AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS num_ct_mri_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%mri%'
     OR LOWER(dh.short_description) LIKE '%computed tomography%'
     OR LOWER(dh.short_description) LIKE '%magnetic resonance%'
  GROUP BY h.hadm_id
)
SELECT
  CASE
    WHEN pa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN pa.los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_category,
  COUNT(DISTINCT pa.hadm_id) AS patient_count,
  AVG(COALESCE(cmp.num_ct_mri_procedures, 0)) AS mean_ct_mri_procedures_per_admission
FROM pancreatitis_admissions pa
LEFT JOIN ct_mri_procedures cmp
  ON pa.hadm_id = cmp.hadm_id
GROUP BY los_category
ORDER BY los_category;