WITH copd_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.anchor_age = 50
    AND p.gender = 'F'
    AND (
      -- ICD-10 J44.x or ICD-9 496
      (d.icd_version = 9 AND d.icd_code = '496')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'J44%')
    )
)

, sodium_itemids AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%sodium%'
    AND LOWER(fluid) = 'serum'
)

, nadir_sodium_per_admission AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    MIN(le.valuenum) AS nadir_sodium
  FROM
    copd_admissions ca
    JOIN physionet-data.mimiciv_3_1_hosp.labevents le
      ON ca.subject_id = le.subject_id AND ca.hadm_id = le.hadm_id
    JOIN sodium_itemids si
      ON le.itemid = si.itemid
  WHERE
    le.valuenum IS NOT NULL
  GROUP BY
    ca.subject_id, ca.hadm_id
)

SELECT
  STDDEV(nadir_sodium) AS stddev_nadir_serum_sodium
FROM
  nadir_sodium_per_admission
WHERE
  nadir_sodium IS NOT NULL
;