WITH ultrasound_events AS (
  -- Chartevents: ultrasound measurements
  SELECT ce.hadm_id
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ultra%' OR LOWER(di.label) LIKE '%echo%'
    AND ce.value IS NOT NULL

  UNION ALL

  -- Procedureevents: formal ultrasound/echo procedures
  SELECT pe.hadm_id
  FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ultra%' OR LOWER(di.label) LIKE '%echo%'
    AND pe.value IS NOT NULL
),

ultrasound_counts_per_admission AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM ultrasound_events
  GROUP BY hadm_id
),

admission_icu_summary AS (
  SELECT 
    a.hadm_id,
    a.admission_type,
    SUM(i.los) AS total_los_days  -- Sum all ICU stays per admission
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE')
  GROUP BY a.hadm_id, a.admission_type
)

SELECT
  CASE 
    WHEN ais.admission_type = 'EMERGENCY' THEN 'ED'
    WHEN ais.admission_type = 'ELECTIVE' THEN 'Elective'
  END AS admission_type,
  CASE 
    WHEN ais.total_los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ais.total_los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  AVG(uc.ultrasound_count) AS mean_ultrasounds_per_admission,
  MIN(uc.ultrasound_count) AS min_ultrasounds_per_admission,
  MAX(uc.ultrasound_count) AS max_ultrasounds_per_admission
FROM admission_icu_summary ais
JOIN ultrasound_counts_per_admission uc
  ON ais.hadm_id = uc.hadm_id
WHERE ais.total_los_days BETWEEN 1 AND 7
GROUP BY 
  CASE 
    WHEN ais.admission_type = 'EMERGENCY' THEN 'ED'
    WHEN ais.admission_type = 'ELECTIVE' THEN 'Elective'
  END,
  CASE 
    WHEN ais.total_los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ais.total_los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END
ORDER BY admission_type, los_group;