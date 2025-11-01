WITH heart_failure_admissions AS (
  SELECT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE
    -- ICD-10 heart failure: I50.x; ICD-9: 428.x
    (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
),
male_65_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age = 65
),
serum_sodium_itemids AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%sodium%'
    AND LOWER(fluid) = 'serum'
),
min_sodium_per_admission AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.valuenum) AS min_sodium
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN serum_sodium_itemids ssi ON l.itemid = ssi.itemid
    INNER JOIN heart_failure_admissions hfa ON l.subject_id = hfa.subject_id AND l.hadm_id = hfa.hadm_id
    INNER JOIN male_65_patients m65 ON l.subject_id = m65.subject_id
  WHERE
    l.valuenum IS NOT NULL
  GROUP BY
    l.subject_id, l.hadm_id
)
SELECT
  MIN(min_sodium) AS min_admission_serum_sodium
FROM
  min_sodium_per_admission;