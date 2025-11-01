WITH dvt_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(d.long_title) LIKE '%deep vein thrombosis%'
    OR LOWER(d.long_title) LIKE '%dvt%'
    OR LOWER(d.long_title) LIKE '%venous thrombosis%'
),

admission_los_icu AS (
  SELECT 
    da.hadm_id,
    da.admittime,
    da.dischtime,
    DATETIME_DIFF(da.dischtime, da.admittime, DAY) AS los_days,
    CASE 
      WHEN DATETIME_DIFF(da.dischtime, da.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATETIME_DIFF(da.dischtime, da.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    CASE 
      WHEN EXISTS (SELECT 1 FROM physionet-data.mimiciv_3_1_icu.icustays i WHERE i.hadm_id = da.hadm_id) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_status
  FROM dvt_admissions da
  WHERE DATETIME_DIFF(da.dischtime, da.admittime, DAY) BETWEEN 1 AND 8
),

noninvasive_diagnostics AS (
  SELECT hadm_id, COUNT(*) AS diagnostic_count
  FROM (
    -- Lab events: D-dimer and other relevant labs
    SELECT le.hadm_id
    FROM physionet-data.mimiciv_3_1_hosp.labevents le
    JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
    WHERE LOWER(dl.label) LIKE '%d-dimer%' OR LOWER(dl.label) LIKE '%d dimer%'
    
    UNION ALL
    
    -- Chart events: imaging and ECG
    SELECT ce.hadm_id
    FROM physionet-data.mimiciv_3_1_icu.chartevents ce
    JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
    WHERE LOWER(di.label) LIKE '%ultrasound%'
       OR LOWER(di.label) LIKE '%doppler%'
       OR LOWER(di.label) LIKE '%ct%'
       OR LOWER(di.label) LIKE '%mri%'
       OR LOWER(di.label) LIKE '%xray%'
       OR LOWER(di.label) LIKE '%ecg%'
       OR LOWER(di.label) LIKE '%electrocardiogram%'
  ) combined
  GROUP BY hadm_id
)

SELECT 
  al.icu_status,
  al.los_group,
  COUNT(*) AS admission_count,
  AVG(COALESCE(nd.diagnostic_count, 0)) AS mean_noninvasive_diagnostics_per_admission
FROM admission_los_icu al
LEFT JOIN noninvasive_diagnostics nd ON al.hadm_id = nd.hadm_id
WHERE al.los_group IS NOT NULL
GROUP BY al.icu_status, al.los_group
ORDER BY al.icu_status, al.los_group;