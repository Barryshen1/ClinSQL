WITH RelevantAdmissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age = 70
), Diagnoses AS (
  SELECT
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.seq_num = 1
), ICDCodes AS (
  SELECT
    icd.icd_code,
    icd_desc.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd_desc
    ON icd.icd_code = icd_desc.icd_code
  WHERE
    icd_desc.long_title LIKE '%upper GI bleeding%'
)
SELECT
  PERCENTILE_CONT(0.75, los) AS percentile_75_los
FROM (
  SELECT
    ra.hadm_id,
    TIMESTAMP_DIFF(ra.dischtime, ra.admittime, DAY) AS los
  FROM
    RelevantAdmissions AS ra
  INNER JOIN
    Diagnoses AS diag
    ON ra.hadm_id = diag.hadm_id
  INNER JOIN
    ICDCodes AS icd
    ON diag.icd_code = icd.icd_code
);