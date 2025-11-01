WITH ami_admissions AS (
  -- Filter female patients aged 52-62 with emergency AMI admission (primary dx I21*)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn_first_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type = 'EMERGENCY'
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I21%'
    AND icd.long_title LIKE '%myocardial infarction%'
),
first_troponin AS (
  -- First troponin T >0.01 ng/mL per patient (across all admissions, but filtered to AMI window in final join)
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum AS first_troponin,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE li.itemid IN (3012, 3013, 53227)  -- Exact Troponin T item IDs
    AND le.valuenum > 0.01
    AND le.valueuom = 'ng//mL'  -- Escaped '/' for BigQuery string literal
    AND le.charttime IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime) = 1
)
SELECT 
  COUNT(DISTINCT aa.subject_id) AS patient_count,
  COUNT(DISTINCT aa.hadm_id) AS admission_count,
  ROUND(AVG(aa.anchor_age), 2) AS mean_age,
  ROUND(AVG(DATE_DIFF(aa.dischtime, aa.admittime, DAY)), 2) AS mean_los_days,
  COUNT(DISTINCT ft.subject_id) AS patients_with_troponin,
  ROUND(AVG(ft.first_troponin), 4) AS mean_first_troponin,
  ROUND(MIN(ft.first_troponin), 4) AS min_first_troponin,
  ROUND(MAX(ft.first_troponin), 4) AS max_first_troponin,
  ROUND(STDDEV(ft.first_troponin), 4) AS stddev_first_troponin,
  SUM(aa.hospital_expire_flag) AS mortality_count,
  ROUND(100.0 * SUM(aa.hospital_expire_flag) / COUNT(DISTINCT aa.hadm_id), 2) AS mortality_rate_percent
FROM ami_admissions aa
INNER JOIN first_troponin ft
  ON aa.subject_id = ft.subject_id
  AND ft.hadm_id = aa.hadm_id  -- Ensure troponin during AMI admission
  AND ft.charttime >= aa.admittime
  AND ft.charttime <= aa.dischtime
WHERE aa.rn_first_adm = 1  -- Limit to first AMI adm per patient
;