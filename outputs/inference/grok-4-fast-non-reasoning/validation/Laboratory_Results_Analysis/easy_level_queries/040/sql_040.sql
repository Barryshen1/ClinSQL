WITH dka_admissions AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age = 58
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND (
      d.icd_code LIKE 'E10.1%' OR 
      d.icd_code LIKE 'E13.1%'
    )
),
glucose_peaks AS (
  SELECT 
    da.subject_id,
    da.hadm_id,
    MAX(le.valuenum) AS peak_glucose
  FROM dka_admissions da
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON da.subject_id = le.subject_id 
    AND da.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
    AND li.label = 'GLUCOSE'  -- Serum glucose
    AND le.charttime >= da.admittime
    AND le.charttime <= da.dischtime
  GROUP BY da.subject_id, da.hadm_id
  HAVING peak_glucose IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(peak_glucose, 0.5) OVER () AS median_peak_glucose
FROM glucose_peaks;