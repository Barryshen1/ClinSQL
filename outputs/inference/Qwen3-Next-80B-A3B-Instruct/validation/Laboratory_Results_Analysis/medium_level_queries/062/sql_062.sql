WITH acs_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    AND (
      (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%' OR di.icd_code LIKE '413%' OR di.icd_code LIKE '414%'))
      OR
      (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I24%'))
    )
),
first_hstnt AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin%' 
    AND LOWER(dl.label) LIKE '%hs%' 
    AND LOWER(dl.label) LIKE '%t%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/L'
),
hstnt_with_category AS (
  SELECT 
    aa.hadm_id,
    aa.admittime,
    aa.dischtime,
    fh.valuenum,
    CASE 
      WHEN fh.valuenum < 14 THEN 'Normal'
      WHEN fh.valuenum BETWEEN 14 AND 39 THEN 'Borderline'
      WHEN fh.valuenum >= 40 THEN 'Myocardial Injury'
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