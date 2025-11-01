WITH aki_patients AS (
  -- Identify primary AKI admissions for women aged 52-62
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 0 AND 1  -- Age at admission approx
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_version = 10  -- Correct integer for ICD-10
    AND REGEXP_CONTAINS(d.icd_code, r'^N17\..*')  -- Precise AKI ICD-10 codes (N17.0-N17.9)
    AND a.hospital_expire_flag = 0  -- Exclude deaths
    AND a.admission_type != 'ELECTIVE'  -- Focus on acute admissions
    -- Ensure this is a primary AKI admission (not a readmission from prior AKI)
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_prior
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a_prior
        ON d_prior.hadm_id = a_prior.hadm_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd_prior
        ON d_prior.icd_code = icd_prior.icd_code 
        AND d_prior.icd_version = icd_prior.icd_version
      WHERE d_prior.subject_id = a.subject_id
        AND a_prior.dischtime < a.admittime
        AND DATE_DIFF(a.admittime, a_prior.dischtime, DAY) <= 30
        AND d_prior.icd_version = 10
        AND REGEXP_CONTAINS(d_prior.icd_code, r'^N17\..*')
        AND a_prior.hospital_expire_flag = 0
    )
),

readmissions AS (
  -- Detect 30-day readmissions per patient, ordered by discharge time
  SELECT 
    ap.subject_id,
    ap.hadm_id AS index_hadm_id,
    a.dischtime AS index_dischtime,
    -- Binary readmit flag: 1 if any readmit within 30 days after this discharge
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a3
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
          ON a3.hadm_id = d3.hadm_id
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd3
          ON d3.icd_code = icd3.icd_code AND d3.icd_version = icd3.icd_version
        WHERE a3.subject_id = ap.subject_id
          AND a3.hadm_id != ap.hadm_id
          AND a3.hospital_expire_flag = 0
          AND a3.admission_type != 'ELECTIVE'
          AND a3.admittime > a.dischtime
          AND DATE_DIFF(a3.admittime, a.dischtime, DAY) <= 30
          AND d3.seq_num = 1  -- Any readmission (primary dx not restricted to AKI)
          AND d3.icd_version = 10
      ) THEN 1 
      ELSE 0 
    END AS readmit_count
  FROM aki_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ap.hadm_id = a.hadm_id
  -- Ensure this is an index admission (no readmission status from prior non-AKI)
  WHERE NOT EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a_prior
    WHERE a_prior.subject_id = ap.subject_id
      AND a_prior.hadm_id != ap.hadm_id
      AND a_prior.dischtime < a.admittime
      AND DATE_DIFF(a.admittime, a_prior.dischtime, DAY) <= 30
      AND a_prior.hospital_expire_flag = 0
      AND a_prior.admission_type != 'ELECTIVE'
  )
)

-- Compute per-encounter standard deviation of readmission count
SELECT 
  STDDEV(readmit_count) AS per_encounter_stddev_30day_readmission
FROM readmissions;