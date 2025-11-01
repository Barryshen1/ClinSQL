WITH dialysis_adms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE (icd_version = 9 AND icd_code IN ('39.95', '54.98'))
     OR (icd_version = 10 AND icd_code LIKE '5A1D%')
)
SELECT STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS sd_los_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN dialysis_adms da
  ON a.subject_id = da.subject_id AND a.hadm_id = da.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 44 AND 54
  AND a.dischtime IS NOT NULL;