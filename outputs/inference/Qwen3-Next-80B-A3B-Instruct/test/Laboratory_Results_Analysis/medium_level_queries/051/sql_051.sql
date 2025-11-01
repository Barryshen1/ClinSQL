WITH acs_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 80 AND 90
    AND p.gender = 'M'
    AND (
      d.icd_code LIKE 'I21%' 
      OR d.icd_code LIKE 'I22%' 
      OR d.icd_code LIKE 'I23%' 
      OR d.icd_code = 'I24.9'
      OR LOWER(d_icd.long_title) LIKE '%acute coronary syndrome%'
    )
),
first_hstnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems di ON l.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%hs-tn%' 
    OR LOWER(di.label) LIKE '%high sensitivity troponin t%'
    OR LOWER(di.label) LIKE '%troponin t, high sensitivity%'
    AND l.valuenum IS NOT NULL
),
hstnt_with_category AS (
  SELECT 
    aa.hadm_id,
    aa.admittime,
    aa.dischtime,
    fh.valuenum,
    CASE 
      WHEN fh.valuenum < 14 THEN 'Normal'
      WHEN fh.valuenum < 40 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS hstnt_category
  FROM acs_admissions aa
  INNER JOIN first_hstnt fh ON aa.hadm_id = fh.hadm_id
  WHERE fh.rn = 1
)
SELECT 
  hstnt_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)), 2) AS mean_hospital_los_days
FROM hstnt_with_category
GROUP BY hstnt_category
ORDER BY hstnt_category;