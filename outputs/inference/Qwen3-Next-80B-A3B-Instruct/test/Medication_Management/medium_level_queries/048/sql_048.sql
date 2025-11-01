WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data`.mimiciv_3_1_hosp.admissions a
  JOIN 
    `physionet-data`.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 65 AND 75
    AND p.gender = 'F'
    AND (a.dischtime - a.admittime) >= INTERVAL '96 HOUR'
),

diabetes_hf_admissions AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime
  FROM 
    cohort fa
  JOIN 
    `physionet-data`.mimiciv_3_1_hosp.diagnoses_icd di ON fa.hadm_id = di.hadm_id
  JOIN 
    `physionet-data`.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE 
    (did.icd_code LIKE '250%' AND did.icd_version = 9) OR
    (did.icd_code LIKE 'E10%' OR did.icd_code LIKE 'E11%' OR did.icd_code LIKE 'E13%') OR
    (did.icd_code LIKE '428%' AND did.icd_version = 9) OR
    (did.icd_code LIKE 'I50%')
),

insulin_orders AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.medication,
    p.frequency,
    p.basal_rate,
    p.doses_per_24_hrs,
    CASE 
      WHEN LOWER(p.medication) LIKE '%glargine%' OR LOWER(p.medication) LIKE '%detemir%' OR LOWER(p.medication) LIKE '%nph%' 
        THEN 'basal'
      WHEN LOWER(p.medication) LIKE '%lispro%' OR LOWER(p.medication) LIKE '%aspart%' OR LOWER(p.medication) LIKE '%regular%' 
        THEN 'bolus'
      WHEN LOWER(p.frequency) LIKE '%sliding%' OR LOWER(p.frequency) LIKE '%prn%' 
        THEN 'sliding-scale'
      ELSE NULL
    END AS regimen
  FROM 
    `physionet-data`.mimiciv_3_1_hosp.pharmacy p
  INNER JOIN 
    diabetes_hf_admissions d ON p.hadm_id = d.hadm_id
  WHERE 
    LOWER(p.medication) LIKE '%insulin%'
    AND p.starttime IS NOT NULL
),

time_windows AS (
  SELECT 
    io.hadm_id,
    io.regimen,
    io.starttime,
    d.admittime,
    d.dischtime,
    CASE 
      WHEN io.starttime >= d.admittime AND io.starttime <= d.admittime + INTERVAL '48 HOUR' THEN 'first_48h'
      WHEN io.starttime >= d.dischtime - INTERVAL '48 HOUR' AND io.starttime <= d.dischtime THEN 'final_48h'
      ELSE NULL
    END AS time_window
  FROM 
    insulin_orders io
  JOIN 
    diabetes_hf_admissions d ON io.hadm_id = d.hadm_id
  WHERE 
    io.regimen IS NOT NULL
),

regimen_counts AS (
  SELECT 
    time_window,
    regimen,
    COUNT(DISTINCT hadm_id) AS patient_count
  FROM 
    time_windows
  WHERE 
    time_window IN ('first_48h', 'final_48h')
  GROUP BY 
    time_window, regimen
),

total_patients AS (
  SELECT COUNT(*) AS total FROM diabetes_hf_admissions
),

final_report AS (
  SELECT 
    rc.regimen,
    ROUND(100.0 * SUM(CASE WHEN rc.time_window = 'first_48h' THEN rc.patient_count ELSE 0 END) / tp.total, 2) AS pct_first_48h,
    ROUND(100.0 * SUM(CASE WHEN rc.time_window = 'final_48h' THEN rc.patient_count ELSE 0 END) / tp.total, 2) AS pct_final_48h
  FROM 
    regimen_counts rc
  CROSS JOIN 
    total_patients tp
  WHERE 
    rc.regimen IN ('basal', 'bolus', 'sliding-scale')
  GROUP BY 
    rc.regimen, tp.total
)

-- Add basal-bolus as a combined category: patients who had both basal and bolus in each window
-- We need to compute basal-bolus separately by checking co-occurrence per patient per window
, basal_bolus_patients AS (
  SELECT 
    tw.time_window,
    tw.hadm_id
  FROM 
    time_windows tw
  WHERE 
    tw.regimen IN ('basal', 'bolus')
  GROUP BY 
    tw.time_window, tw.hadm_id
  HAVING 
    COUNT(DISTINCT tw.regimen) = 2
),

basal_bolus_counts AS (
  SELECT 
    time_window,
    'basal-bolus' AS regimen,
    COUNT(DISTINCT hadm_id) AS patient_count
  FROM 
    basal_bolus_patients
  GROUP BY 
    time_window
),

final_report_with_basal_bolus AS (
  SELECT regimen, pct_first_48h, pct_final_48h FROM final_report
  UNION ALL
  SELECT 
    bb.regimen,
    ROUND(100.0 * SUM(CASE WHEN bb.time_window = 'first_48h' THEN bb.patient_count ELSE 0 END) / tp.total, 2) AS pct_first_48h,
    ROUND(100.0 * SUM(CASE WHEN bb.time_window = 'final_48h' THEN bb.patient_count ELSE 0 END) / tp.total, 2) AS pct_final_48h
  FROM 
    basal_bolus_counts bb
  CROSS JOIN 
    total_patients tp
  GROUP BY 
    bb.regimen, tp.total
)

SELECT 
  regimen,
  pct_first_48h,
  pct_final_48h
FROM 
  final_report_with_basal_bolus
ORDER BY 
  regimen;