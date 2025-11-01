WITH ischemic_stroke_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.dischtime,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M' AND
    (LOWER(di.long_title) LIKE '%ischemic stroke%' OR LOWER(di.long_title) LIKE '%cerebral infarction%')
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY l.valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY l.valuenum) AS iqr
FROM ischemic_stroke_admissions isa
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON isa.hadm_id = l.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
WHERE
  LOWER(dl.label) LIKE '%glucose%' AND
  DATE(l.charttime) = DATE(isa.dischtime);