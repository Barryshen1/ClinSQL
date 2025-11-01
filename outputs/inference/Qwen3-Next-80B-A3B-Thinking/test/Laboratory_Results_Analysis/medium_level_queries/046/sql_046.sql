WITH ami_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'I21%'
),
troponin_first AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
)
SELECT 
  COUNT(*) AS N,
  AVG(p.anchor_age) AS mean_age,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los,
  AVG(tf.valuenum) AS troponin_summary
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id
JOIN ami_patients am 
  ON p.subject_id = am.subject_id AND a.hadm_id = am.hadm_id
JOIN troponin_first tf 
  ON p.subject_id = tf.subject_id AND a.hadm_id = tf.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 83 AND 93
  AND tf.rn = 1
  AND tf.valuenum > tf.ref_range_upper;