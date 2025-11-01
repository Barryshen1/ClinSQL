WITH ischemic_stroke_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
  AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 45 AND 55
  AND dicd.long_title LIKE '%Ischemic stroke%'
),
hemoglobin_results AS (
  SELECT isa.hadm_id, l.valuenum, l.charttime, isa.admittime
  FROM ischemic_stroke_admissions isa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON isa.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Hemoglobin'
  AND l.charttime BETWEEN isa.admittime AND TIMESTAMP_ADD(isa.admittime, INTERVAL 24 HOUR)
)
SELECT MIN(valuenum) AS min_hemoglobin
FROM hemoglobin_results;