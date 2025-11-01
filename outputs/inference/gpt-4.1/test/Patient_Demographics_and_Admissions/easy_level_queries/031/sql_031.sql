WITH hf_icd_codes AS (
  -- List of ICD codes for heart failure (ICD-9: 428.x, ICD-10: I50.x)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
),
hf_admissions AS (
  -- Admissions with HF diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN hf_icd_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
),
eligible_patients AS (
  -- Women aged 38-48 with HF admission
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
first_hf_admission AS (
  -- First HF admission per eligible patient
  SELECT
    t.subject_id,
    t.hadm_id,
    t.admittime,
    t.dischtime,
    t.deathtime,
    t.hospital_expire_flag
  FROM (
    SELECT
      e.subject_id,
      h.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.deathtime,
      adm.hospital_expire_flag,
      ROW_NUMBER() OVER (PARTITION BY e.subject_id ORDER BY adm.admittime ASC) AS rn
    FROM eligible_patients e
    INNER JOIN hf_admissions h
      ON e.subject_id = h.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON h.hadm_id = adm.hadm_id
  ) t
  WHERE t.rn = 1
    AND (t.hospital_expire_flag = 0 OR t.deathtime IS NULL) -- exclude deaths during index admission
),
readmissions AS (
  -- Find 30-day readmissions after first HF admission
  SELECT
    f.subject_id,
    f.hadm_id AS index_hadm_id,
    f.dischtime,
    MIN(a.admittime) AS readmit_admittime
  FROM first_hf_admission f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id
    AND a.admittime > f.dischtime
    AND a.admittime <= TIMESTAMP_ADD(f.dischtime, INTERVAL 30 DAY)
    AND a.hadm_id != f.hadm_id
  GROUP BY f.subject_id, f.hadm_id, f.dischtime
)
SELECT
  COUNT(DISTINCT f.subject_id) AS num_patients,
  COUNT(DISTINCT r.subject_id) AS num_readmitted,
  SAFE_DIVIDE(COUNT(DISTINCT r.subject_id), COUNT(DISTINCT f.subject_id)) AS avg_30day_readmission_rate
FROM first_hf_admission f
LEFT JOIN readmissions r
  ON f.subject_id = r.subject_id
  AND f.hadm_id = r.index_hadm_id;