WITH hf_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
    )
),
first_hf_admission AS (
  SELECT
    subject_id,
    MIN(admittime) AS first_admit_time
  FROM hf_patients
  GROUP BY subject_id
),
first_hf_details AS (
  SELECT
    f.subject_id,
    adm.hadm_id AS first_hadm_id,
    adm.admittime,
    adm.dischtime
  FROM first_hf_admission f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON f.subject_id = adm.subject_id
   AND f.first_admit_time = adm.admittime
),
readmissions AS (
  SELECT
    fd.subject_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm2
        WHERE adm2.subject_id = fd.subject_id
          AND adm2.admittime > fd.dischtime
          AND DATE_DIFF(adm2.admittime, fd.dischtime, DAY) <= 30
      )
      THEN 1 ELSE 0
    END AS readmit_within_30
  FROM first_hf_details fd
)
SELECT
  COUNTIF(readmit_within_30 = 1) / COUNT(*) AS avg_30day_readmission_rate
FROM readmissions;