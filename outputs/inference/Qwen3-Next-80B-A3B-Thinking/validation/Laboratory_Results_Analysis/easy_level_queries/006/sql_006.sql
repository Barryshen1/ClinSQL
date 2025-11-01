WITH qualifying_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 50
    AND (d_icd.long_title LIKE '%COPD%' OR d_icd.long_title LIKE '%chronic obstructive pulmonary disease%')
)
SELECT
  STDDEV(min_sodium) AS std_dev_nadir_sodium
FROM (
  SELECT
    a.hadm_id,
    MIN(lab.valuenum) AS min_sodium
  FROM
    qualifying_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON a.hadm_id = lab.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
    ON lab.itemid = d_lab.itemid
  WHERE
    lab.charttime BETWEEN a.admittime AND a.dischtime
    AND d_lab.label LIKE '%Sodium%'
    AND lab.valuenum IS NOT NULL
  GROUP BY
    a.hadm_id
) AS nadir_values;