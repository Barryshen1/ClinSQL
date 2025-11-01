WITH acs_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      LOWER(did.long_title) LIKE LOWER('%acute coronary syndrome%')
      OR LOWER(did.long_title) LIKE LOWER('%unstable angina%')
      OR LOWER(did.long_title) LIKE LOWER('%myocardial infarction%')
      OR LOWER(did.long_title) LIKE LOWER('%ischemic heart disease%')
      OR did.icd_code IN ('I21', 'I22', 'I23', 'I24', 'I20.0', '410', '411', '413')
    )
),
first_troponin_t AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE LOWER('%troponin t%')
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.valuenum > 0
),
troponin_categories AS (
  SELECT 
    aa.hadm_id,
    aa.admittime,
    aa.dischtime,
    ft.valuenum,
    CASE 
      WHEN ft.valuenum <= 0.04 THEN 'Normal'
      WHEN ft.valuenum <= 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM acs_admissions aa
  JOIN first_troponin_t ft ON aa.hadm_id = ft.hadm_id
  WHERE ft.rn = 1
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)), 2) AS avg_los
FROM troponin_categories
GROUP BY troponin_category
ORDER BY troponin_category;