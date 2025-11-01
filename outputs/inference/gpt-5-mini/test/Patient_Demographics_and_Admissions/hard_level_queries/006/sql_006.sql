WITH principal_diag AS (
  -- principal diagnosis per admission, with descriptive title
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1  -- principal diagnosis
),
hemorrhagic_principal AS (
  -- admissions whose principal diagnosis description indicates hemorrhagic stroke
  SELECT
    pd.subject_id,
    pd.hadm_id,
    pd.long_title
  FROM
    principal_diag pd
  WHERE
    pd.long_title IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(pd.long_title),
      r'hemorrhag|haemorrhag|subarachnoid|intracerebral|intracranial.*hemorrag|intracranial hemorrhag')
),
cohort_admissions AS (
  -- admissions that meet all cohort criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    hemorrhagic_principal hp
  ON
    a.hadm_id = hp.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    -- robustly detect transfer from another hospital in admission_location
    AND a.admission_location IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(a.admission_location), r'transfer.*hospital|from hospital')
    -- ensure we have an admission id and time
    AND a.hadm_id IS NOT NULL
    AND a.admittime IS NOT NULL
),
index_per_subject AS (
  -- pick the earliest qualifying admission per subject (index admission)
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
  FROM
    cohort_admissions
)
-- final count: number of index admissions in the cohort (one per subject)
SELECT
  COUNT(*) AS index_admissions_count
FROM
  index_per_subject
WHERE
  rn = 1;