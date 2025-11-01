WITH acs_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%acute coronary syndrome%'
    OR d_icd.long_title LIKE '%myocardial infarction%'
    OR d_icd.long_title LIKE '%unstable angina%'
),
eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN acs_admissions acs
    ON a.hadm_id = acs.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),
troponin_first AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE di.label LIKE '%Troponin T%'
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los
FROM (
  SELECT 
    CASE
      WHEN tf.valueuom IN ('ng/mL', 'ug/L') THEN
        CASE
          WHEN tf.valuenum <= 0.01 THEN 'Normal'
          WHEN tf.valuenum > 0.01 AND tf.valuenum <= 0.04 THEN 'Borderline'
          ELSE 'Elevated'
        END
      WHEN tf.valueuom = 'pg/mL' THEN
        CASE
          WHEN tf.valuenum <= 10 THEN 'Normal'
          WHEN tf.valuenum > 10 AND tf.valuenum <= 40 THEN 'Borderline'
          ELSE 'Elevated'
        END
      ELSE NULL
    END AS troponin_category,
    a.dischtime,
    a.admittime
  FROM eligible_patients a
  JOIN troponin_first tf ON a.hadm_id = tf.hadm_id
  WHERE tf.rn = 1
    AND tf.valuenum IS NOT NULL
) categorized
WHERE troponin_category IS NOT NULL
GROUP BY troponin_category;