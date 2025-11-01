WITH platelet_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) LIKE '%platelet count%'
),
patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 87
    AND (
      (d.icd_version = 10
       AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
      OR
      (d.icd_version = 9
       AND d.icd_code >= '430' AND d.icd_code <= '432')
    )
),
platelet_values AS (
  SELECT le.valuenum
  FROM patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON p.subject_id = le.subject_id
    AND p.hadm_id = le.hadm_id
  INNER JOIN platelet_items pi
    ON le.itemid = pi.itemid
  WHERE le.valuenum IS NOT NULL
    AND DATE(le.charttime) = DATE(p.dischtime)
    AND le.charttime >= p.admittime
    AND le.charttime <= p.dischtime
)
SELECT
  PERCENTILE_CONT(0.75 IGNORE NULLS) OVER (ORDER BY valuenum ASC) AS platelet_75th_percentile
FROM platelet_values
LIMIT 1;