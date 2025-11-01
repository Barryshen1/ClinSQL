WITH acs_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND d.icd_code IN ('I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9', 'I24.0', 'I24.8', 'I24.9')
),

first_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
    AND l.valuenum > 0
),

troponin_categories AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.anchor_age,
    ft.valuenum,
    CASE
      WHEN ft.valuenum < 0.04 THEN 'Normal'
      WHEN ft.valuenum BETWEEN 0.04 AND 0.09 THEN 'Borderline'
      WHEN ft.valuenum >= 0.10 THEN 'Elevated'
    END AS troponin_category,
    DATE_DIFF(ap.dischtime, ap.admittime, DAY) AS los_days
  FROM acs_patients ap
  INNER JOIN first_troponin ft
    ON ap.hadm_id = ft.hadm_id
  WHERE ft.rn = 1
)

SELECT
  troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM troponin_categories
WHERE troponin_category IS NOT NULL
GROUP BY troponin_category
ORDER BY troponin_category;