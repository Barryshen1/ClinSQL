WITH hf_diagnoses AS (
  SELECT 
    di.subject_id, 
    di.hadm_id, 
    di.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code 
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),
hf_class AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN MIN(seq_num) = 1 THEN 'Primary'
      ELSE 'Secondary' 
    END AS hf_type
  FROM hf_diagnoses
  GROUP BY hadm_id
),
admissions_filtered AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    hc.hf_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN hf_class hc 
    ON a.hadm_id = hc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_procs AS (
  SELECT 
    pi.hadm_id,
    COUNT(*) AS num_imaging
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pi.icd_code = dp.icd_code 
    AND pi.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ct%'
     OR LOWER(dp.long_title) LIKE '%computed tomography%'
     OR LOWER(dp.long_title) LIKE '%mri%'
     OR LOWER(dp.long_title) LIKE '%magnetic resonance%'
  GROUP BY pi.hadm_id
)
SELECT 
  af.hf_type,
  CASE 
    WHEN af.los <= 3 THEN '1-3 days'
    ELSE '4-7 days'
  END AS los_group,
  AVG(COALESCE(ip.num_imaging, 0)) AS mean_ct_mri,
  MIN(COALESCE(ip.num_imaging, 0)) AS min_ct_mri,
  MAX(COALESCE(ip.num_imaging, 0)) AS max_ct_mri
FROM admissions_filtered af
LEFT JOIN imaging_procs ip 
  ON af.hadm_id = ip.hadm_id
GROUP BY af.hf_type, los_group
ORDER BY hf_type, los_group;