WITH first_hstnt AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS hstnt_value,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin%' 
    AND LOWER(dl.label) LIKE '%high sensitivity%'
    AND le.valuenum IS NOT NULL
),
cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    f.hstnt_value,
    CASE 
      WHEN f.hstnt_value <= 14 THEN 'Normal'
      WHEN f.hstnt_value BETWEEN 15 AND 39 THEN 'Borderline'
      WHEN f.hstnt_value >= 40 THEN 'Myocardial Injury'
    END AS hstnt_category,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  JOIN first_hstnt f
    ON a.hadm_id = f.hadm_id AND f.rn = 1
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      LOWER(did.long_title) LIKE '%chest pain%'
      OR LOWER(did.long_title) LIKE '%acute myocardial infarction%'
    )
    AND di.icd_version = 10
)
SELECT 
  hstnt_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM cohort
WHERE hstnt_category IS NOT NULL
GROUP BY hstnt_category
ORDER BY hstnt_category;