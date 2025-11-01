WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
),

surgical_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.services
  WHERE LOWER(curr_service) = 'surg'
),

high_risk_drugs AS (
  SELECT LOWER(drug) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  GROUP BY drug_name
  HAVING SUM(CASE
    WHEN LOWER(drug) IN (
      'warfarin', 'heparin', 'insulin', 'fentanyl', 'morphine',
      'digoxin', 'potassium chloride', 'phenytoin', 'lithium', 'theophylline'
    ) THEN 1 ELSE 0 END) > 0
),

medication_complexity AS (
  SELECT
    pa.hadm_id,
    SUM(CASE WHEN hr.drug_name IS NOT NULL THEN 2 ELSE 1 END) AS complexity_score
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON pa.hadm_id = pr.hadm_id
  LEFT JOIN high_risk_drugs hr
    ON LOWER(pr.drug) = hr.drug_name
  WHERE pr.starttime >= pa.admittime
    AND pr.starttime < DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
    AND pr.drug IS NOT NULL
  GROUP BY pa.hadm_id
),

admissions_with_outcomes AS (
  SELECT
    pa.*,
    mc.complexity_score,
    -- Calculate LOS in days
    DATETIME_DIFF(pa.dischtime, pa.admittime, SECOND) / (24 * 60 * 60) AS los_days,
    -- Flag for 30-day readmission
    CASE
      WHEN LEAD(pa.admittime) OVER (PARTITION BY pa.subject_id ORDER BY pa.admittime) <= DATETIME_ADD(pa.dischtime, INTERVAL 30 DAY)
        THEN 1 ELSE 0 END AS thirty_day_readmit
  FROM patient_admissions pa
  INNER JOIN surgical_admissions sa ON pa.hadm_id = sa.hadm_id
  LEFT JOIN medication_complexity mc ON pa.hadm_id = mc.hadm_id
  WHERE pa.dischtime IS NOT NULL
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM admissions_with_outcomes
  WHERE complexity_score IS NOT NULL
)

SELECT
  quartile,
  COUNT(*) AS count_patients,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(thirty_day_readmit) * 100, 2) AS thirty_day_readmission_pct
FROM quartiles
GROUP BY quartile
ORDER BY quartile;