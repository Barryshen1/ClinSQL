WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
upper_gi_bleed_admissions AS (
  SELECT
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(pa.dischtime, pa.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.hadm_id = d.hadm_id AND pa.subject_id = d.subject_id
  WHERE
    pa.gender = 'M'
    AND pa.age_at_admission BETWEEN 74 AND 84
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_version = 10  -- ICD-10 codes only
    AND (
      -- Upper GI bleed ICD-10 codes
      d.icd_code LIKE 'K92%' OR
      (d.icd_code LIKE 'K25%' AND LENGTH(d.icd_code) >= 4 AND SUBSTR(d.icd_code, 4, 1) IN ('0', '2', '3', '5')) OR
      (d.icd_code LIKE 'K26%' AND LENGTH(d.icd_code) >= 4 AND SUBSTR(d.icd_code, 4, 1) IN ('0', '2', '3', '5')) OR
      (d.icd_code LIKE 'K27%' AND LENGTH(d.icd_code) >= 4 AND SUBSTR(d.icd_code, 4, 1) IN ('0', '2', '3', '5')) OR
      (d.icd_code LIKE 'K28%' AND LENGTH(d.icd_code) >= 4 AND SUBSTR(d.icd_code, 4, 1) IN ('0', '2', '3', '5')) OR
      d.icd_code IN ('I850', 'I853')
    )
    AND pa.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS los_25th_percentile
FROM upper_gi_bleed_admissions;