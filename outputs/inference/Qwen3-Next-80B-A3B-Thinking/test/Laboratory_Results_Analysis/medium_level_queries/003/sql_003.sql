WITH ischemic_diagnosis AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.seq_num = 1
    AND di.long_title LIKE '%ischemic heart disease%'
),
troponin_first AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE di.label LIKE '%TROPONIN%T%HIGH SENS%'
),
filtered_patients AS (
  SELECT 
    t.valuenum
  FROM troponin_first t
  JOIN ischemic_diagnosis i ON t.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    t.rn = 1
    AND t.valuenum > t.ref_range_upper
    AND p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 36 AND 46
    AND t.charttime >= a.admittime
    AND t.ref_range_upper IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(valuenum, 0.25) WITHIN GROUP (ORDER BY valuenum) AS p25,
  PERCENTILE_CONT(valuenum, 0.5) WITHIN GROUP (ORDER BY valuenum) AS p50,
  PERCENTILE_CONT(valuenum, 0.75) WITHIN GROUP (ORDER BY valuenum) AS p75,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val
FROM filtered_patients;