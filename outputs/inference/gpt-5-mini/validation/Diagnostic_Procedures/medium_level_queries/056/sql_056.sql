WITH pancreatitis_admissions AS (
  -- Admissions for female patients age 47-57 with a diagnosis labeled "acute pancreatitis"
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE LOWER(COALESCE(dicd.long_title, '')) LIKE '%acute pancreatitis%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
),

imaging_counts AS (
  -- Count CT/MRI HCPCS events that occur during each admission
  SELECT
    a.hadm_id,
    COUNT(*) AS imaging_count
  FROM pancreatitis_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
    ON a.hadm_id = he.hadm_id
   AND a.subject_id = he.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON he.hcpcs_cd = dh.code
  WHERE
    -- ensure event occurred during the hospital admission (chartdate is a DATE)
    he.chartdate BETWEEN DATE(a.admittime) AND DATE(a.dischtime)
    -- identify CT / MRI by keywords in the short_description or long_description
    AND REGEXP_CONTAINS(
      UPPER(CONCAT(IFNULL(he.short_description, ''), ' ', IFNULL(dh.long_description, ''))),
      r'\bCT\b|\bMRI\b|TOMOGRAPH|MAGNETIC'
    )
  GROUP BY a.hadm_id
)

SELECT
  CASE
    WHEN pa.los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN pa.los_days BETWEEN 5 AND 8 THEN '5-8'
  END AS los_group,
  COUNT(*) AS admission_count,
  -- average number of CT/MRI procedures per admission (treat NULL as 0)
  ROUND(AVG(COALESCE(ic.imaging_count, 0)), 3) AS mean_ct_mri_per_admission
FROM pancreatitis_admissions pa
LEFT JOIN imaging_counts ic
  ON pa.hadm_id = ic.hadm_id
WHERE pa.los_days BETWEEN 1 AND 4 OR pa.los_days BETWEEN 5 AND 8
GROUP BY los_group
ORDER BY los_group;