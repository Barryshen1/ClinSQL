WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.insurance,
    a.admission_location,
    dd.long_title AS diagnosis,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%transfer%from%hosp%'
    AND di.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%hemorrhagic stroke%'
      OR LOWER(dd.long_title) LIKE '%intracerebral hemorrhage%'
    )
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    age_at_admit
  FROM (
    SELECT
      subject_id,
      hadm_id,
      age_at_admit,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM cohort
  )
  WHERE rn = 1
    AND age_at_admit >= 36
    AND age_at_admit <= 46
)
SELECT COUNT(*) AS total_index_admissions
FROM index_admissions;