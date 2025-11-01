WITH index_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.insurance,
    adm.admission_location,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission,
    -- Rank admissions by time to get index (first) admission
    ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS admission_order
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    adm.subject_id = p.subject_id
),
principal_diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE
    di.seq_num = 1  -- Principal diagnosis
)
SELECT
  COUNT(*) AS total_index_admissions
FROM
  index_admissions ia
JOIN
  principal_diagnoses pd
ON
  ia.hadm_id = pd.hadm_id
WHERE
  ia.admission_order = 1  -- Only index admissions
  AND ia.gender = 'F'
  AND ia.insurance = 'Medicare'
  AND ia.admission_location = 'Emergency Department'
  AND ia.age_at_admission >= 62
  AND ia.age_at_admission <= 72
  AND (
    (pd.icd_code = '780.2' AND pd.icd_version = 9)
    OR (pd.icd_code = 'R55' AND pd.icd_version = 10)
  );