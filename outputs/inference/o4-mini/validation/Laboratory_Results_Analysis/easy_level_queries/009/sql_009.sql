WITH female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND (
      LOWER(dd.long_title) LIKE '%myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%unstable angina%'
    )
  GROUP BY
    a.subject_id,
    a.hadm_id
),
troponin_nadirs AS (
  SELECT
    fa.hadm_id,
    MIN(le.valuenum) AS nadir_trop
  FROM
    female_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON fa.subject_id = le.subject_id
      AND fa.hadm_id = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON le.itemid = li.itemid
  WHERE
    LOWER(li.label) LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
  GROUP BY
    fa.hadm_id
)
SELECT
  APPROX_QUANTILES(nadir_trop, 100)[OFFSET(25)] AS troponin_nadir_p25
FROM
  troponin_nadirs;