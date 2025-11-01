WITH hemorrhagic_stroke_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I60') OR
      REGEXP_CONTAINS(icd_code, r'^I61') OR
      REGEXP_CONTAINS(icd_code, r'^I62')
    ))
    -- ICD-9
    OR (icd_version = 9 AND (
      icd_code = '430' OR
      icd_code = '431' OR
      REGEXP_CONTAINS(icd_code, r'^432')
    ))
),
primary_hemorrhagic_stroke_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN hemorrhagic_stroke_codes codes
    ON diag.icd_code = codes.icd_code AND diag.icd_version = codes.icd_version
  WHERE
    diag.seq_num = 1 -- primary diagnosis
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 37 AND 47
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(
    TIMESTAMP_DIFF(dischtime, admittime, DAY),
    4
  )[3] AS hospital_los_75th_percentile_days
FROM primary_hemorrhagic_stroke_admissions
WHERE
  TIMESTAMP_DIFF(dischtime, admittime, DAY) >= 0;