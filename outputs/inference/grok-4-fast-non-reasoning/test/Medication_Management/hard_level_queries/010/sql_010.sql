WITH patient_admissions AS (
  -- Base cohort: male patients aged 61-71, inpatient admissions
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- LOS in hours (BigQuery-compatible)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year  -- Ensure age at admission
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.dischtime > a.admittime
),
med_complexity AS (
  -- First 24h distinct medications per admission (proxy for complexity score)
  SELECT 
    adm.hadm_id,
    COUNT(DISTINCT LOWER(e.medication)) AS complexity_score
  FROM 
    patient_admissions adm
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON e.hadm_id = adm.hadm_id
  WHERE 
    e.charttime >= adm.admittime
    AND e.charttime < TIMESTAMP_ADD(adm.admittime, INTERVAL 24 HOUR)
    AND e.medication IS NOT NULL
    AND TRIM(e.medication) != ''
  GROUP BY 
    adm.hadm_id
),
base_cohort AS (
  -- Combine admissions with complexity (0 if no meds)
  SELECT 
    pa.*,
    COALESCE(mc.complexity_score, 0) AS complexity_score
  FROM 
    patient_admissions pa
  LEFT JOIN 
    med_complexity mc
  ON pa.hadm_id = mc.hadm_id
),
readmissions AS (
  -- Flag 30-day readmissions via self-join (fixed aggregation)
  SELECT 
    base.hadm_id,
    MAX(CASE 
      WHEN nexta.admittime >= base.dischtime 
      AND nexta.admittime <= TIMESTAMP_ADD(base.dischtime, INTERVAL 30 DAY)
      AND nexta.subject_id = base.subject_id
      AND nexta.hadm_id != base.hadm_id  -- Exclude self
      THEN 1 
      ELSE 0 
    END) AS has_readmission_30d
  FROM 
    base_cohort base
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` nexta
  ON base.subject_id = nexta.subject_id
  GROUP BY 
    base.hadm_id, base.dischtime, base.subject_id
),
final_cohort AS (
  -- Add readmission flag and quintile
  SELECT 
    base.*,
    COALESCE(r.has_readmission_30d, 0) AS readmission_flag,  -- Keep as INT
    NTILE(5) OVER (ORDER BY base.complexity_score) AS complexity_quintile
  FROM 
    base_cohort base
  LEFT JOIN 
    readmissions r
  ON base.hadm_id = r.hadm_id
)
-- Aggregate by quintile
SELECT 
  complexity_quintile,
  COUNT(*) AS num_patients,
  ROUND(AVG(complexity_score), 2) AS mean_complexity_score,
  ROUND(AVG(los_hours), 2) AS avg_los_hours,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS in_hospital_mortality_rate,
  ROUND(AVG(CAST(readmission_flag AS FLOAT64)), 4) AS readmission_30d_rate
FROM 
  final_cohort
GROUP BY 
  complexity_quintile
ORDER BY 
  complexity_quintile;