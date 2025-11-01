WITH aki_diagnosis_type AS (
  SELECT
    di.hadm_id,
    CASE WHEN MIN(di.seq_num) = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.long_title LIKE '%acute kidney injury%' OR d.long_title LIKE '%acute renal failure%'
  GROUP BY di.hadm_id
),
patient_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 64 AND 74
    AND a.dischtime IS NOT NULL
),
imaging_count AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE d.category = 'Radiology'
  GROUP BY h.hadm_id
)
SELECT
  CASE
    WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  adt.diagnosis_type,
  APPROX_QUANTILES(COALESCE(ic.imaging_count, 0), 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(COALESCE(ic.imaging_count, 0), 100)[OFFSET(75)] - APPROX_QUANTILES(COALESCE(ic.imaging_count, 0), 100)[OFFSET(25)] AS iqr
FROM patient_admissions pa
JOIN aki_diagnosis_type adt ON pa.hadm_id = adt.hadm_id
LEFT JOIN imaging_count ic ON pa.hadm_id = ic.hadm_id
WHERE pa.los_days BETWEEN 1 AND 7
GROUP BY los_group, diagnosis_type;