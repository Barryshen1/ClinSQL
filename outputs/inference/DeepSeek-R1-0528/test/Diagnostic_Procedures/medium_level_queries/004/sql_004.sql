WITH base_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
hf_admissions AS (
  SELECT 
    d.hadm_id,
    MIN(d.seq_num) AS min_hf_seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN base_admissions ba ON d.hadm_id = ba.hadm_id
  WHERE 
    (d.icd_version = 9 AND d.icd_code LIKE '428%') 
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
  GROUP BY d.hadm_id
),
procedures_icd_ct_mri AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS cnt
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%computed tomography%' 
    OR LOWER(d.long_title) LIKE '%ct%'
    OR LOWER(d.long_title) LIKE '%magnetic resonance%'
    OR LOWER(d.long_title) LIKE '%mri%'
  GROUP BY p.hadm_id
),
hcpcs_ct_mri AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS cnt
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%computed tomography%' 
    OR LOWER(d.long_description) LIKE '%ct%'
    OR LOWER(d.long_description) LIKE '%magnetic resonance%'
    OR LOWER(d.long_description) LIKE '%mri%'
  GROUP BY h.hadm_id
),
admission_procedures AS (
  SELECT 
    ha.hadm_id,
    COALESCE(p.cnt, 0) + COALESCE(h.cnt, 0) AS total_ct_mri
  FROM hf_admissions ha
  LEFT JOIN procedures_icd_ct_mri p ON ha.hadm_id = p.hadm_id
  LEFT JOIN hcpcs_ct_mri h ON ha.hadm_id = h.hadm_id
),
final_data AS (
  SELECT 
    ba.hadm_id,
    ba.los_days,
    CASE 
      WHEN ha.min_hf_seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_group,
    ap.total_ct_mri
  FROM base_admissions ba
  INNER JOIN hf_admissions ha ON ba.hadm_id = ha.hadm_id
  LEFT JOIN admission_procedures ap ON ba.hadm_id = ap.hadm_id
)
SELECT 
  diagnosis_group,
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_group,
  AVG(total_ct_mri) AS mean_ct_mri,
  MIN(total_ct_mri) AS min_ct_mri,
  MAX(total_ct_mri) AS max_ct_mri,
  COUNT(*) AS num_admissions
FROM final_data
GROUP BY diagnosis_group, los_group
ORDER BY diagnosis_group, los_group;