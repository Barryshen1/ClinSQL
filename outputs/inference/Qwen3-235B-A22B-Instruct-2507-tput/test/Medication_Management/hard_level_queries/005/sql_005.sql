WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 43 AND 53
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY') -- Inpatient only
),

hepatic_failure AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'K72%'
    AND di.icd_version = 10
),

medication_complexity AS (
  SELECT
    hf.hadm_id,
    COUNT(DISTINCT pr.drug) AS medication_count
  FROM hepatic_failure hf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON hf.hadm_id = pr.hadm_id
    AND pr.starttime >= hf.admittime
    AND pr.starttime < DATETIME_ADD(hf.admittime, INTERVAL 72 HOUR)
    AND pr.starttime IS NOT NULL
  GROUP BY hf.hadm_id
),

quintiles AS (
  SELECT
    hf.*,
    COALESCE(mc.medication_count, 0) AS med_count,
    NTILE(5) OVER (ORDER BY COALESCE(mc.medication_count, 0)) AS quintile
  FROM hepatic_failure hf
  LEFT JOIN medication_complexity mc ON hf.hadm_id = mc.hadm_id
),

readmissions AS (
  SELECT
    q.*,
    -- Check if readmitted within 30 days
    CASE WHEN NEXT_ADMISSION.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
         THEN 1 ELSE 0 END AS thirty_day_readmit
  FROM quintiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.admissions NEXT_ADMISSION
    ON q.subject_id = NEXT_ADMISSION.subject_id
    AND NEXT_ADMISSION.admittime > q.dischtime
    AND NEXT_ADMISSION.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
    AND NEXT_ADMISSION.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
),

hospital_los AS (
  SELECT
    r.quintile,
    COUNT(*) AS n,
    MIN(r.med_count) AS min_score,
    MAX(r.med_count) AS max_score,
    AVG(r.med_count) AS mean_score,
    AVG(TIMESTAMP_DIFF(r.dischtime, r.admittime, MINUTE)) / (24*60) AS mean_los_days,
    AVG(r.hospital_expire_flag) * 100 AS mortality_pct,
    AVG(COALESCE(r.thirty_day_readmit, 0)) * 100 AS readmission_30day_pct
  FROM readmissions r
  GROUP BY r.quintile
  ORDER BY quintile
)

SELECT
  quintile,
  n,
  min_score,
  max_score,
  ROUND(mean_score, 2) AS mean_score,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(readmission_30day_pct, 2) AS readmission_30day_pct
FROM hospital_los;