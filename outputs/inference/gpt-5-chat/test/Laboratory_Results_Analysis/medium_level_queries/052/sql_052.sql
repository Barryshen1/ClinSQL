WITH ami_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code
   AND diag.icd_version = d_icd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
      OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
    )
),
troponin_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE di.label LIKE '%Troponin I%'
    AND le.valuenum IS NOT NULL
    AND le.hadm_id IS NOT NULL
),
first_trop AS (
  SELECT t.subject_id,
         t.hadm_id,
         t.charttime,
         t.valuenum,
         ROW_NUMBER() OVER (PARTITION BY t.subject_id, t.hadm_id ORDER BY t.charttime) AS rn
  FROM troponin_labs t
  JOIN ami_admissions a
    ON t.subject_id = a.subject_id
   AND t.hadm_id = a.hadm_id
)
SELECT 
  CASE 
    WHEN valuenum <= 0.04 THEN 'Normal (≤0.04)'
    WHEN valuenum < 0.40 THEN 'Borderline (0.04–0.40)'
    ELSE 'Elevated (≥0.40)'
  END AS trop_category,
  COUNT(*) AS count_patients,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_patients,
  ROUND(AVG(valuenum), 3) AS mean_trop,
  ROUND(APPROX_QUANTILES(valuenum, 2)[OFFSET(1)], 3) AS median_trop,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 3) AS q1_trop,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)], 3) AS q3_trop,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 3) AS iqr_trop
FROM first_trop
WHERE rn = 1
GROUP BY trop_category
ORDER BY trop_category;