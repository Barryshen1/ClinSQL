WITH patients_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 90 AND 100
),

hf_diagnoses AS (
  SELECT
    pa.hadm_id,
    d.seq_num
  FROM patients_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON pa.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%heart failure%'
),

hf_types AS (
  SELECT
    hadm_id,
    CASE
      WHEN SUM(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) > 0 THEN 'primary'
      ELSE 'secondary'
    END AS hf_type
  FROM hf_diagnoses
  GROUP BY hadm_id
),

los AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM patients_admissions
),

mri_ct_procedures AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_mri_ct
  FROM (
    SELECT
      h.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
    WHERE d.short_description LIKE '%CT%' OR d.short_description LIKE '%MRI%'
    UNION ALL
    SELECT
      p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE d.long_title LIKE '%MRI%' OR d.long_title LIKE '%CT%'
  ) AS procedures
  GROUP BY hadm_id
)

SELECT
  CASE
    WHEN l.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN l.los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_group,
  h.hf_type,
  COUNT(*) AS admission_count,
  AVG(COALESCE(m.num_mri_ct, 0)) AS mean_mri_ct_per_admission
FROM hf_types h
JOIN los l ON h.hadm_id = l.hadm_id
LEFT JOIN mri_ct_procedures m ON h.hadm_id = m.hadm_id
WHERE l.los_days BETWEEN 1 AND 7
GROUP BY los_group, hf_type;