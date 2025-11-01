WITH ami_diagnoses AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN di.seq_num = 1 AND 
                 ((di.icd_version = 9 AND di.icd_code LIKE '410%') OR 
                  (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')))
             THEN 1 ELSE 0 END) AS is_primary_ami,
    MAX(CASE WHEN 
                 ((di.icd_version = 9 AND di.icd_code LIKE '410%') OR 
                  (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')))
             THEN 1 ELSE 0 END) AS has_ami
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),

patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS hospital_los,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    ad.is_primary_ami,
    CASE 
      WHEN ad.is_primary_ami = 1 THEN 'primary'
      WHEN ad.has_ami = 1 THEN 'secondary'
      ELSE NULL 
    END AS ami_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN ami_diagnoses ad
    ON a.hadm_id = ad.hadm_id
  WHERE p.gender = 'M'
    AND ad.has_ami = 1
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
    AND a.dischtime IS NOT NULL
),

imaging_procedures AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  -- Fixed: Join admissions to access admission timestamps
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON h.hadm_id = a.hadm_id
  WHERE SAFE_CAST(h.hcpcs_cd AS INT64) BETWEEN 70000 AND 76499
    AND h.chartdate >= DATE(a.admittime)  -- Properly qualified column
    AND h.chartdate <= DATE(a.dischtime)  -- Properly qualified column
  GROUP BY h.hadm_id
),

admission_stats AS (
  SELECT
    pa.hadm_id,
    pa.ami_type,
    CASE 
      WHEN pa.hospital_los >= 1 AND pa.hospital_los <= 3 THEN '1-3 days'
      WHEN pa.hospital_los >= 4 AND pa.hospital_los <= 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_group,
    COALESCE(ip.imaging_count, 0) AS imaging_count
  FROM patient_admissions pa
  LEFT JOIN imaging_procedures ip
    ON pa.hadm_id = ip.hadm_id
  WHERE pa.hospital_los IS NOT NULL
)

SELECT
  ami_type,
  los_group,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(500)] AS median_imaging,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(750)] - 
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(250)] AS iqr_imaging
FROM admission_stats
WHERE los_group IS NOT NULL
GROUP BY ami_type, los_group
ORDER BY ami_type, los_group;