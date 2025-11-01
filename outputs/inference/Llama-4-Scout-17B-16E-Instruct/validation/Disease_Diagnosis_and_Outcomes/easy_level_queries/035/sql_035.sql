WITH 
  -- Identify primary upper GI bleeding admissions
  gi_bleeding_icd9 AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      CAST(icd_code AS STRING) IN ('456.0', '530.7', '531.0', '531.1', '531.2', '531.3', '531.4', '531.5', '531.6', '531.7', 
                    '532.0', '532.1', '532.2', '532.3', '532.4', '532.5', '532.6', '532.7', '533.0', '533.1', 
                    '533.2', '533.3', '533.4', '533.5', '533.6', '533.7')
      AND icd_version = '9'
  ),
  gi_bleeding_icd10 AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      CAST(icd_code AS STRING) IN ('K92.0', 'K22.0', 'K31.0', 'K25.0', 'K26.0', 'K27.0', 'K28.0', 'K29.0', 'K30.0', 'K31.2')
      AND icd_version = '10'
  ),
  gi_bleeding_admissions AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      gi_bleeding_icd9
    UNION DISTINCT
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      gi_bleeding_icd10
  ),
  patient_info AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime, 
      p.gender, 
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),
  filtered_admissions AS (
    SELECT 
      subject_id, 
      hadm_id, 
      admittime, 
      dischtime, 
      gender, 
      anchor_age
    FROM 
      patient_info
    JOIN 
      gi_bleeding_admissions
    ON 
      patient_info.subject_id = gi_bleeding_admissions.subject_id
      AND patient_info.hadm_id = gi_bleeding_admissions.hadm_id
    WHERE 
      gender = 'M'
      AND anchor_age = 70
  )

-- Calculate hospital length of stay and 75th percentile
SELECT 
  APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, DAY), 0.75)[OFFSET(1)] AS percentile_75_los
FROM 
  filtered_admissions;