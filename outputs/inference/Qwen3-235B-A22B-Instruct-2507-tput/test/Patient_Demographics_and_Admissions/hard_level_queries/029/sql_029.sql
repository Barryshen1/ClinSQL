WITH index_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.admission_type,
    adm.insurance,
    ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 46 AND 56
    AND adm.insurance = 'Medicare'
    AND adm.admission_type = 'TRANSFER'
),
principal_diagnoses AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE
    di.seq_num = 1  -- Principal diagnosis
    AND di.icd_version = 10
    AND di.icd_code LIKE 'S72%'
)
SELECT
  COUNT(*) AS cohort_count
FROM
  index_admissions ia
INNER JOIN
  principal_diagnoses pd
ON
  ia.subject_id = pd.subject_id AND ia.hadm_id = pd.hadm_id
WHERE
  ia.rn = 1;