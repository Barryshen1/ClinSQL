WITH
-- Get female patients aged 45-55 at admission
female_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admission_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
),

-- Get HF admissions with LOS 1-7 days
hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    d.seq_num,
    d.icd_code,
    di.long_title,
    CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN female_patients fp ON a.subject_id = fp.subject_id
  WHERE
    -- Heart failure ICD-10 codes (I50.*)
    d.icd_code LIKE 'I50%'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND (fp.anchor_year + fp.anchor_age) = EXTRACT(YEAR FROM a.admittime)
),

-- Count CT/MRI procedures per admission
imaging_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE
    -- CT head codes (70450-70498)
    (h.hcpcs_cd BETWEEN '70450' AND '70498')
    -- MRI brain codes (70551-70559)
    OR (h.hcpcs_cd BETWEEN '70551' AND '70559')
  GROUP BY hadm_id
)

-- Final aggregation
SELECT
  ha.diagnosis_type,
  ha.los_category,
  COUNT(DISTINCT ha.hadm_id) AS admission_count,
  AVG(ic.ct_mri_count) AS mean_ct_mri_per_admission,
  MIN(ic.ct_mri_count) AS min_ct_mri_per_admission,
  MAX(ic.ct_mri_count) AS max_ct_mri_per_admission
FROM hf_admissions ha
LEFT JOIN imaging_counts ic ON ha.hadm_id = ic.hadm_id
GROUP BY
  ha.diagnosis_type,
  ha.los_category
ORDER BY
  ha.diagnosis_type,
  ha.los_category;