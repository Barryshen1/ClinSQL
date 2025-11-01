WITH age_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
),

stroke_diagnoses AS (
  SELECT 
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%intracerebral hemorrhage%'
     OR LOWER(d.long_title) LIKE '%hemorrhagic stroke%'
     OR LOWER(d.long_title) LIKE '%nontraumatic subarachnoid hemorrhage%'
     OR (di.icd_code LIKE 'I61%' AND di.icd_version = 10)
     OR (di.icd_code LIKE 'I62%' AND di.icd_version = 10)
),

index_stroke_admissions AS (
  SELECT 
    af.*
  FROM age_filtered af
  INNER JOIN stroke_diagnoses s
    ON af.hadm_id = s.hadm_id
),

medication_complexity AS (
  SELECT 
    isa.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drugs
  FROM index_stroke_admissions isa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON isa.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= isa.admittime
    AND pr.starttime < DATETIME_ADD(isa.admittime, INTERVAL 7 DAY)
  GROUP BY isa.hadm_id
),

quintiles AS (
  SELECT 
    isa.*,
    mc.unique_drugs,
    NTILE(5) OVER (ORDER BY mc.unique_drugs) AS drug_quintile
  FROM index_stroke_admissions isa
  INNER JOIN medication_complexity mc
    ON isa.hadm_id = mc.hadm_id
),

readmission_flag AS (
  SELECT 
    q.*,
    CASE 
      WHEN NEXT_ADMISSION.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY) 
      THEN 1 ELSE 0 
    END AS thirty_day_readmission
  FROM quintiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.admissions NEXT_ADMISSION
    ON q.subject_id = NEXT_ADMISSION.subject_id
    AND NEXT_ADMISSION.admittime > q.dischtime
    AND NEXT_ADMISSION.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
),

final_outcomes AS (
  SELECT 
    drug_quintile,
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS inpatient_mortality_rate,
    AVG(CAST(thirty_day_readmission AS FLOAT64)) AS thirty_day_readmission_rate,
    COUNT(*) AS n_patients
  FROM readmission_flag
  GROUP BY drug_quintile
  ORDER BY drug_quintile
)

SELECT 
  drug_quintile,
  ROUND(avg_los_days, 2) AS avg_los_days,
  ROUND(inpatient_mortality_rate, 3) AS inpatient_mortality_rate,
  ROUND(thirty_day_readmission_rate, 3) AS thirty_day_readmission_rate,
  n_patients
FROM final_outcomes;