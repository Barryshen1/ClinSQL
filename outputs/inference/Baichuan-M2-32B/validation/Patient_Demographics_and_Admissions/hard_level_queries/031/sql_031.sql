WITH base_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_type,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    d.icd_code,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND ((d.icd_code = '780.2' AND d.icd_version = 9) OR (d.icd_code = 'R55' AND d.icd_version = 10))
    AND a.admission_type = 'Emergency'
    AND a.insurance = 'Medicare'
    AND p.gender = 'F'
),
age_calculated AS (
  SELECT
    *,
    TIMESTAMP_DIFF(admittime, DATE(CAST(anchor_year - anchor_age AS STRING) || '-01-01'), YEAR) AS age_at_admission
  FROM base_data
),
filtered_admissions AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM age_calculated
  WHERE age_at_admission BETWEEN 62 AND 72
)
SELECT COUNT(*) AS total_index_admissions
FROM filtered_admissions
WHERE rn = 1;