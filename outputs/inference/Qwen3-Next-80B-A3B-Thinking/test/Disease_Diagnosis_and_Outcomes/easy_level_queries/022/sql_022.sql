WITH filtered_admissions AS (
  SELECT
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 71 AND 81
    AND diag.seq_num = 1
    AND (LOWER(d_diag.long_title) LIKE '%ischemic stroke%' OR LOWER(d_diag.long_title) LIKE '%cerebral infarction%')
),
quartiles AS (
  SELECT
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS q1,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS q3
  FROM filtered_admissions
)
SELECT q3 - q1 AS iqr
FROM quartiles;