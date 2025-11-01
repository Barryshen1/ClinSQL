WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND (
      LOWER(ddx.long_title) LIKE '%acute coronary%'
      OR LOWER(ddx.long_title) LIKE '%myocardial infarction%'
      OR LOWER(ddx.long_title) LIKE '%angina%'
    )
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  SELECT 
    la.subject_id,
    la.hadm_id,
    la.valuenum,
    la.valueuom,
    la.charttime
  FROM (
    SELECT 
      l.subject_id,
      l.hadm_id,
      l.valuenum,
      l.valueuom,
      l.charttime,
      ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_items ti
      ON l.itemid = ti.itemid
    WHERE l.valuenum IS NOT NULL
      AND LOWER(l.valueuom) = 'ng/ml'
  ) la
  WHERE la.rn = 1
),
combined AS (
  SELECT 
    acs.subject_id,
    acs.hadm_id,
    acs.admittime,
    acs.dischtime,
    ft.valuenum,
    CASE
      WHEN ft.valuenum <= 0.03 THEN 'Normal'
      WHEN ft.valuenum > 0.03 AND ft.valuenum <= 0.10 THEN 'Borderline'
      WHEN ft.valuenum > 0.10 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM acs_admissions acs
  JOIN first_troponin ft
    ON acs.hadm_id = ft.hadm_id
)
SELECT 
  troponin_category,
  COUNT(*) AS admission_count,
  ROUND( COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(DATETIME_DIFF(dischtime, admittime, DAY)), 2) AS avg_los_days
FROM combined
GROUP BY troponin_category
ORDER BY troponin_category;