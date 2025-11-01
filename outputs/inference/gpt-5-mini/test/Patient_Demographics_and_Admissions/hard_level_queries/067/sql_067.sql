WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    a.insurance,
    a.admission_location,
    di.icd_code,
    di.icd_version,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
    AND di.seq_num = 1  -- principal diagnosis
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    p.anchor_age BETWEEN 43 AND 53
    AND (p.gender = 'F' OR LOWER(p.gender) = 'female')
    -- completed admission: discharged and not expired in hospital
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0
    -- Medicare (case-insensitive substring match to capture variants)
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    -- admitted from emergency department (case-insensitive substring match)
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%emerg%'
    -- principal diagnosis matches bowel/intestinal obstruction in long_title
    AND (
      LOWER(COALESCE(d.long_title, '')) LIKE '%obstruct%'
      AND (
        LOWER(COALESCE(d.long_title, '')) LIKE '%bowel%'
        OR LOWER(COALESCE(d.long_title, '')) LIKE '%intestin%'
      )
    )
),

index_per_subject AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cohort_admissions
)

SELECT
  COUNT(*) AS index_admission_count
FROM index_per_subject
WHERE rn = 1;