WITH acs_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 10 AND icd_code IN (
      'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 
      'I24.0', 'I25.1', 'I25.2', 'I25.3', 'I25.4', 'I25.5', 
      'I25.6', 'I25.7', 'I25.8', 'I25.9'
    )) OR
    (icd_version = 9 AND icd_code IN (
      '410', '411', '412', '413', '414', '415', '416', '417', '418', '419'
    ))
),
acs_admissions AS (
  SELECT DISTINCT d.hadm_id, d.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN acs_codes ac 
    ON d.icd_code = ac.icd_code AND d.icd_version = ac.icd_version
),
admission_acs_type AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      WHEN MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) = 1 THEN 'secondary'
      ELSE NULL 
    END AS acs_type
  FROM acs_admissions
  GROUP BY hadm_id
),
patient_age AS (
  SELECT 
    p.subject_id,
    p.anchor_year,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
eligible_admissions AS (
  SELECT 
    pa.hadm_id,
    pa.subject_id,
    pa.admittime,
    pa.dischtime,
    pa.age_at_admission,
    aat.acs_type
  FROM patient_age pa
  JOIN admission_acs_type aat 
    ON pa.hadm_id = aat.hadm_id
  WHERE pa.age_at_admission BETWEEN 77 AND 87
),
admission_los AS (
  SELECT 
    hadm_id,
    DATEDIFF(dischtime, admittime) AS los_days
  FROM eligible_admissions
),
los_group AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL 
    END AS los_group
  FROM admission_los
),
radiography_counts AS (
  SELECT 
    ea.hadm_id,  -- Fixed: Changed from 'a.hadm_id' to 'ea.hadm_id'
    COUNT(*) AS ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
    ON h.hcpcs_cd = dh.code
  JOIN eligible_admissions ea 
    ON h.subject_id = ea.subject_id 
    AND h.chartdate BETWEEN DATE(ea.admittime) AND DATE(ea.dischtime)
  WHERE 
    dh.long_description LIKE '%CT%' OR 
    dh.long_description LIKE '%radiography%' OR 
    dh.long_description LIKE '%X-ray%' OR 
    dh.long_description LIKE '%radiograph%'
  GROUP BY ea.hadm_id  -- Fixed: Changed from 'a.hadm_id' to 'ea.hadm_id'
),
final_data AS (
  SELECT 
    ea.acs_type,
    lg.los_group,
    COALESCE(rc.ct_count, 0) AS ct_count
  FROM eligible_admissions ea
  JOIN los_group lg 
    ON ea.hadm_id = lg.hadm_id
  LEFT JOIN radiography_counts rc 
    ON ea.hadm_id = rc.hadm_id
  WHERE lg.los_group IS NOT NULL
)
SELECT 
  acs_type,
  los_group,
  COUNT(*) AS num_admissions,
  AVG(ct_count) AS mean_ct_count,
  MIN(ct_count) AS min_ct_count,
  MAX(ct_count) AS max_ct_count
FROM final_data
GROUP BY acs_type, los_group
ORDER BY acs_type, los_group;