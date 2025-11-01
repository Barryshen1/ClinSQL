WITH filtered_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.admission_type IN ('Elective', 'Emergency', 'Urgent', 'Trauma')
),

medication_complexity AS (
  SELECT 
    fa.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_drugs
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON fa.hadm_id = p.hadm_id
    AND p.starttime BETWEEN fa.admittime AND fa.admittime + INTERVAL '24' HOUR
  GROUP BY fa.hadm_id
),

readmission_flag AS (
  SELECT 
    a.hadm_id,
    CASE WHEN next_adm.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmission_30d
  FROM filtered_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
    ON a.subject_id = next_adm.subject_id
    AND next_adm.admittime > a.dischtime
    AND next_adm.admittime <= a.dischtime + INTERVAL '30' DAY
),

combined AS (
  SELECT 
    fa.hadm_id,
    DATETIME_DIFF(fa.dischtime, fa.admittime, DAY) AS los_days,
    fa.hospital_expire_flag,
    mc.unique_drugs,
    rf.readmission_30d
  FROM filtered_admissions fa
  LEFT JOIN medication_complexity mc ON fa.hadm_id = mc.hadm_id
  LEFT JOIN readmission_flag rf ON fa.hadm_id = rf.hadm_id
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY unique_drugs) AS quartile
  FROM combined
)

SELECT
  quartile,
  COUNT(*) AS patient_count,
  AVG(los_days) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
  AVG(CAST(readmission_30d AS FLOAT64)) * 100 AS readmission_30d_pct
FROM quartiles
GROUP BY quartile
ORDER BY quartile;