WITH hf_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 65
    AND LOWER(di.long_title) LIKE '%heart failure%'
),
sodium_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS sodium_val
  FROM
    hf_admissions ha
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON ha.subject_id = l.subject_id
      AND ha.hadm_id = l.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON l.itemid = li.itemid
  WHERE
    LOWER(li.label) LIKE '%sodium%'
    AND l.valuenum IS NOT NULL
),
per_admission_min AS (
  SELECT
    hadm_id,
    MIN(sodium_val) AS min_sodium
  FROM
    sodium_labs
  GROUP BY
    hadm_id
)
SELECT
  MIN(min_sodium) AS overall_min_serum_sodium
FROM
  per_admission_min;