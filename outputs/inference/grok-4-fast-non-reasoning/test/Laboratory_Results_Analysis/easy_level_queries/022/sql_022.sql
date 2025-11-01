WITH patient_peaks AS (
  SELECT 
    p.subject_id,
    MAX(ce.valuenum) AS peak_ph
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.subject_id = ce.subject_id 
    AND i.hadm_id = ce.hadm_id 
    AND i.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age >= 18
    AND ce.itemid IN (3837, 220235)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 6.5 AND 8.0
  GROUP BY 
    p.subject_id
  HAVING 
    peak_ph IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(peak_ph, 0.75) OVER() - PERCENTILE_CONT(peak_ph, 0.25) OVER() AS iqr_peak_ph
FROM 
  patient_peaks;