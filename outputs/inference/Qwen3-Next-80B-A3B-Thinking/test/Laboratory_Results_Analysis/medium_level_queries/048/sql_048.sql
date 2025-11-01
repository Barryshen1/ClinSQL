WITH aminec AS (
  SELECT 
    d.hadm_id,
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON d.subject_id = p.subject_id
  WHERE d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I21%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
),
first_hstnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
    ON l.itemid = d.itemid
  WHERE d.label LIKE '%High Sensitivity Troponin T%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
)
SELECT 
  COUNT(a.hadm_id) AS admission_count,
  COUNT(DISTINCT a.subject_id) AS patient_count,
  AVG(fh.valuenum) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY fh.valuenum) AS median,
  (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY fh.valuenum) 
   - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY fh.valuenum)) AS iqr
FROM aminec a
JOIN first_hstnt fh 
  ON a.hadm_id = fh.hadm_id AND fh.rn = 1
WHERE fh.valuenum > 0.01;