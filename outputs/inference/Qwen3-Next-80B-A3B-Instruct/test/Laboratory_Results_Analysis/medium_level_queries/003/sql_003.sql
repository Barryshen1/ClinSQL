WITH ischemic_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    AND d_icd.icd_version = 10
    AND (
      LOWER(d_icd.long_title) LIKE '%ischemic%'
      OR LOWER(d_icd.long_title) LIKE '%heart disease%'
      OR d_icd.icd_code LIKE 'I2%'
    )
),
troponin_first_above_uln AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ia.hadm_id ORDER BY le.charttime) AS rn
  FROM ischemic_admissions ia
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ia.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND LOWER(dl.label) LIKE '%high sensitivity%'
    AND le.valuenum IS NOT NULL
    AND dl.ref_range_upper IS NOT NULL
    AND le.valuenum > dl.ref_range_upper
    AND le.charttime >= ia.admittime
    AND le.charttime <= ia.dischtime
)
SELECT 
  PERCENTILE_CONT(valuenum, 0.25) AS p25,
  PERCENTILE_CONT(valuenum, 0.50) AS p50,
  PERCENTILE_CONT(valuenum, 0.75) AS p75,
  MIN(valuenum) AS min,
  MAX(valuenum) AS max
FROM troponin_first_above_uln
WHERE rn = 1;