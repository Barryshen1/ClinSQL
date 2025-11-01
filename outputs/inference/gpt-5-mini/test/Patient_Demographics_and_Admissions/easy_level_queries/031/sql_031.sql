WITH hf_diagnoses AS (
  -- admissions that have a diagnosis whose long_title mentions "heart failure"
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%'
),

hf_admissions AS (
  -- bring in admission times and patient demographics, restrict to females age 38-48
  SELECT
    h.subject_id,
    h.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM hf_diagnoses h
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

first_hf_per_patient AS (
  -- pick the first (earliest) HF admission per subject
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM hf_admissions
),

index_hf AS (
  -- only keep the first HF admission per patient and exclude in-hospital deaths
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM first_hf_per_patient
  WHERE rn = 1
    AND COALESCE(hospital_expire_flag, 0) = 0
),

readmission_flags AS (
  -- determine for each index admission whether there is any readmission within 30 days
  SELECT
    i.subject_id,
    i.hadm_id AS index_hadm_id,
    i.admittime AS index_admittime,
    i.dischtime AS index_dischtime,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = i.subject_id
          AND a2.admittime > i.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(i.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmitted_within_30d
  FROM index_hf i
)

SELECT
  COUNT(*) AS n_index_patients,
  SUM(readmitted_within_30d) AS n_with_30d_readmit,
  SAFE_DIVIDE(SUM(readmitted_within_30d), COUNT(*)) AS readmission_rate_30d
FROM readmission_flags;