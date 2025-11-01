WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      LOWER(dd.long_title) LIKE '%chest pain%'
      OR LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
    )
),
troponin_lab AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum, le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),
index_troponin AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.los_days,
         t.valuenum, t.valueuom
  FROM cohort c
  JOIN troponin_lab t
    ON c.hadm_id = t.hadm_id
  WHERE t.rn = 1
),
categorized AS (
  SELECT *,
    CASE
      WHEN valuenum <= 14 THEN 'Normal'
      WHEN valuenum > 14 AND valuenum <= 53 THEN 'Borderline'
      WHEN valuenum > 53 THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS category
  FROM index_troponin
)
SELECT category,
       COUNT(*) AS num_admissions,
       ROUND(COUNT(*)*100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
       ROUND(AVG(los_days), 2) AS mean_los_days
FROM categorized
GROUP BY category
ORDER BY category;