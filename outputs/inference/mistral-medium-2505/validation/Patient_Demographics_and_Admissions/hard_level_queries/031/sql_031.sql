WITH female_medicare_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_location,
    -- Calculate age at admission (approximate)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
),

syncope_admissions AS (
  SELECT
    fmp.hadm_id
  FROM
    female_medicare_patients fmp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    fmp.hadm_id = di.hadm_id
  WHERE
    fmp.age_at_admission BETWEEN 62 AND 72
    AND di.seq_num = 1  -- Principal diagnosis
    AND (
      (di.icd_version = 9 AND di.icd_code = '780.2') OR
      (di.icd_version = 10 AND di.icd_code = 'R55')
    )
)

SELECT
  COUNT(DISTINCT hadm_id) AS total_index_admissions
FROM
  syncope_admissions;