WITH admission_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admission_location,
    insurance,
    gender,
    age_at_admission,
    admittime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM
      admission_age
  )
  WHERE rn = 1
),
diagnosis_filtered AS (
  SELECT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    di.seq_num = 1  -- Principal diagnosis
    AND LOWER(d.long_title) LIKE '%osteomyelitis%'
)
SELECT
  COUNT(*) AS count_index_admissions
FROM
  index_admissions ia
JOIN
  diagnosis_filtered df
ON
  ia.hadm_id = df.hadm_id
WHERE
  ia.gender = 'F'
  AND ia.age_at_admission BETWEEN 85 AND 95
  AND ia.insurance = 'Medicare'
  AND (
    LOWER(ia.admission_location) LIKE '%transfer from%'
    OR LOWER(ia.admission_location) LIKE '%skilled nursing%'
  );