WITH 
-- Identify male patients aged 47-57
patients_47_57 AS (
  SELECT subject_id, anchor_age, gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 47 AND 57
),

-- Admissions for these patients
admissions_47_57 AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_47_57 p ON a.subject_id = p.subject_id
),

-- Lab events for creatinine
creatinine_labs AS (
  SELECT l.hadm_id, l.charttime, l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE d.label = 'Creatinine'
)

-- Simplified AKI identification and lab instability score calculation
SELECT 
  a.hadm_id,
  -- Basic AKI identification (KDIGO criteria not fully implemented)
  CASE 
    WHEN MAX(c.valuenum) > 1.5 THEN 'AKI'
    ELSE 'No AKI'
  END AS aki_status
FROM admissions_47_57 a
LEFT JOIN creatinine_labs c ON a.hadm_id = c.hadm_id
GROUP BY a.hadm_id;