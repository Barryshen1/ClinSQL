WITH male_medicare_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location LIKE '%SNF%'  -- Skilled Nursing Facility
),

dehydration_admissions AS (
  SELECT
    mmp.hadm_id,
    mmp.age_at_admission,
    mmp.admission_location,
    mmp.insurance,
    di.icd_code,
    d.long_title AS diagnosis_description
  FROM
    male_medicare_patients mmp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    mmp.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    di.seq_num = 1  -- Principal diagnosis
    AND d.long_title LIKE '%dehydration%'  -- Filter for dehydration
    AND mmp.age_at_admission BETWEEN 43 AND 53
)

SELECT
  COUNT(DISTINCT hadm_id) AS num_admissions
FROM
  dehydration_admissions;