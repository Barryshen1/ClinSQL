WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND di.long_title LIKE '%sepsis%'
    AND a.dischtime IS NOT NULL
)
SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) AS percentile_75
FROM sepsis_admissions sa
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON sa.hadm_id = l.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
WHERE dl.label LIKE '%platelet%'
  AND DATE(l.charttime) = DATE(sa.dischtime)
  AND l.valuenum IS NOT NULL;