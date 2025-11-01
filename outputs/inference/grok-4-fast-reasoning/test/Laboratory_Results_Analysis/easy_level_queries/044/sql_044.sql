WITH qualifying_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND a.hospital_expire_flag = 0
    AND (
      (d.icd_version = 9
       AND (
         d.icd_code LIKE '433%'
         OR d.icd_code LIKE '434%'
         OR d.icd_code = '436'
       ))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr_serum_glucose_mg_dl
FROM qualifying_admissions qa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON qa.hadm_id = l.hadm_id
WHERE l.itemid = 50931
  AND l.valuenum IS NOT NULL
  AND l.valueuom = 'mg/dL'
  AND DATE(l.charttime) = DATE(qa.dischtime);