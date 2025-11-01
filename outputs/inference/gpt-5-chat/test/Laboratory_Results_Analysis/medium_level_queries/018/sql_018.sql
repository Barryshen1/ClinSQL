WITH acs_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.gender, p.anchor_age,
    a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    -- ICD-9 and ICD-10 patterns for ACS
    AND (
      (d.icd_version = 9 AND (
          d.icd_code LIKE '410%'  -- AMI
          OR d.icd_code = '4111'  -- unstable angina
          OR d.icd_code = '4118%' -- other acute/subacute
      ))
      OR
      (d.icd_version = 10 AND (
          d.icd_code LIKE 'I20.0%'  -- unstable angina
          OR d.icd_code LIKE 'I21%' -- AMI
          OR d.icd_code LIKE 'I22%' -- subsequent AMI
      ))
    )
)
, troponin_events AS (
  SELECT l.subject_id, l.hadm_id, l.charttime, l.valuenum, l.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE di.label LIKE 'Troponin T%'
    AND l.valuenum IS NOT NULL
)
, first_troponin AS (
  SELECT t.subject_id, t.hadm_id, t.valuenum, t.valueuom,
         t.charttime
  FROM troponin_events t
  JOIN (
    SELECT hadm_id, MIN(charttime) AS first_charttime
    FROM troponin_events
    GROUP BY hadm_id
  ) tf
    ON t.hadm_id = tf.hadm_id
   AND t.charttime = tf.first_charttime
)
, categorized AS (
  SELECT a.subject_id, a.hadm_id,
    CASE
      WHEN f.valuenum <= 0.03 THEN 'Normal'
      WHEN f.valuenum > 0.03 AND f.valuenum <= 0.1 THEN 'Borderline'
      WHEN f.valuenum > 0.1 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM acs_patients a
  JOIN first_troponin f
    ON a.subject_id = f.subject_id
    AND a.hadm_id = f.hadm_id
)
, stats AS (
  SELECT troponin_category,
         COUNT(*) AS patient_count,
         ROUND(AVG(los),2) AS mean_los
  FROM categorized
  GROUP BY troponin_category
)
SELECT s.troponin_category, 
       s.patient_count,
       ROUND(100.0 * s.patient_count / SUM(s.patient_count) OVER (),2) AS pct,
       s.mean_los
FROM stats s
ORDER BY troponin_category;