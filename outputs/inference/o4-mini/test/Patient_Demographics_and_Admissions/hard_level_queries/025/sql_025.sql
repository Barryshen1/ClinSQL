WITH female_medicare AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.insurance = 'Medicare'
    -- admission_location values are free‐text; we look for transfers from another hospital
    AND LOWER(a.admission_location) LIKE '%transfer%'
    AND LOWER(a.admission_location) LIKE '%hospital%'
),
principal_hf AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    female_medicare
)
SELECT
  COUNT(DISTINCT ia.hadm_id) AS num_index_admissions
FROM
  index_admissions ia
  JOIN principal_hf ph
    ON ia.subject_id = ph.subject_id
   AND ia.hadm_id = ph.hadm_id
WHERE
  ia.rn = 1;