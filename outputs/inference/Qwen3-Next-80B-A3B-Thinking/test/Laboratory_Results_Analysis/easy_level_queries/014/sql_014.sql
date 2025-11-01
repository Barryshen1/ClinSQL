WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id AND a.subject_id = diag.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1
    AND d.long_title LIKE '%gastrointestinal%'
    AND (d.long_title LIKE '%bleeding%' OR d.long_title LIKE '%hemorrhage%')
    AND p.gender = 'F'
    AND p.anchor_age = 45
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lab.valuenum) AS percentile_75
FROM
  filtered_admissions fa
JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` lab
  ON fa.hadm_id = lab.hadm_id AND fa.subject_id = lab.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
  ON lab.itemid = d_lab.itemid
WHERE
  DATE(lab.charttime) = DATE(fa.dischtime)
  AND (d_lab.label LIKE '%Hemoglobin%' OR d_lab.label = 'Hgb');