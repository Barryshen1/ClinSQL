WITH qualifying_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND DATE(a.dischtime) > DATE(a.admittime)
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
aki_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 'ICD-9' AND icd_code LIKE '584.%') 
        OR (icd_version = 'ICD-10' AND icd_code LIKE 'N17%') 
      THEN 1 
      ELSE 0 
    END) AS has_aki,
    MIN(CASE 
      WHEN (icd_version = 'ICD-9' AND icd_code LIKE '584.%') 
        OR (icd_version = 'ICD-10' AND icd_code LIKE 'N17%') 
      THEN seq_num 
    END) AS min_seq_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
admissions_with_aki AS (
  SELECT 
    qa.*,
    CASE 
      WHEN af.has_aki = 1 AND af.min_seq_aki = 1 THEN 'primary'
      WHEN af.has_aki = 1 THEN 'secondary'
      ELSE NULL 
    END AS aki_type,
    CASE 
      WHEN qa.los_days <= 4 THEN '1-4'
      ELSE '5-7'
    END AS los_group
  FROM qualifying_admissions qa
  LEFT JOIN aki_flags af 
    ON qa.hadm_id = af.hadm_id
  WHERE CASE 
          WHEN af.has_aki = 1 AND af.min_seq_aki = 1 THEN 'primary'
          WHEN af.has_aki = 1 THEN 'secondary'
          ELSE NULL 
        END IS NOT NULL
),
imaging AS (
  SELECT 
    pi.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%ct%' 
     OR LOWER(dip.long_title) LIKE '%magnetic resonance%'
  GROUP BY pi.hadm_id
)
SELECT 
  aki_type,
  los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(COALESCE(i.imaging_count, 0)) AS mean_mri_ct_per_admission
FROM admissions_with_aki awa
LEFT JOIN imaging i 
  ON awa.hadm_id = i.hadm_id
GROUP BY aki_type, los_group
ORDER BY aki_type, los_group;