WITH ischemic_pts AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
    AND (
      (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) BETWEEN '410' AND '414')
      OR (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) BETWEEN 'I20' AND 'I25')
    )
),
trop_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_trop AS (
  SELECT
    ip.subject_id,
    ip.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ip.hadm_id ORDER BY le.charttime) AS rn
  FROM ischemic_pts ip
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ip.hadm_id = le.hadm_id
  JOIN trop_itemids ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
)
, first_trop_filtered AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum
  FROM first_trop
  WHERE rn = 1
    AND valuenum > 0.014
)
SELECT
  PERCENTILE_CONT(valuenum, 0.5) OVER() AS median_trop,
  PERCENTILE_CONT(valuenum, 0.25) OVER() AS q1_trop,
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS q3_trop,
  PERCENTILE_CONT(valuenum, 0.75) OVER() - PERCENTILE_CONT(valuenum, 0.25) OVER() AS iqr_trop
FROM first_trop_filtered;