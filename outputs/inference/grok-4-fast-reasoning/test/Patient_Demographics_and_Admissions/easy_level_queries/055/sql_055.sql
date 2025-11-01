WITH pneumonia_adms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    icd_version = 9 AND REGEXP_CONTAINS(icd_code, '^48[0-6]')
  ) OR (
    icd_version = 10 AND REGEXP_CONTAINS(icd_code, '^J(09|1[0-8])')
  )
)
SELECT
  APPROX_QUANTILES(sub.los, 4)[OFFSET(1)] AS p25_los_days
FROM (
  SELECT
    adm.hadm_id,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN pneumonia_adms pa
    ON adm.hadm_id = pa.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND adm.dischtime > adm.admittime
) AS sub;