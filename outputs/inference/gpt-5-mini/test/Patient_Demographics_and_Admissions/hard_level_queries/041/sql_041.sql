WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    a.insurance,
    a.admission_location,
    a.edregtime,
    d.icd_code,
    di.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1 -- principal diagnosis
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    AND (
      LOWER(COALESCE(a.admission_location, '')) LIKE '%emergen%'
      OR a.edregtime IS NOT NULL
    )
    AND LOWER(COALESCE(di.long_title, '')) LIKE '%osteomyelitis%'
),
first_index AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cohort
)
SELECT
  COUNT(*) AS index_hospital_admissions
FROM first_index
WHERE rn = 1;