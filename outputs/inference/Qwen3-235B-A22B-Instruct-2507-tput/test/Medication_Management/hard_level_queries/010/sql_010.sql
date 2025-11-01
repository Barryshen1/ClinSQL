WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), DAY) / 365.25 AS age_at_admit,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  -- Join with diagnoses to filter for hemorrhagic stroke
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND di.icd_version = 10
    AND (
      (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%') -- Intracerebral or nontraumatic SAH
    )
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT') -- Inpatient only
),
-- Filter patients aged 61–71 at admission and take first admission per patient
cohort AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM patient_admissions
    WHERE age_at_admit >= 61 AND age_at_admit <= 71
  ) ranked
  WHERE rn = 1
),
-- Get medication complexity: number of distinct drugs in first 24h of admission
medication_complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT pr.drug) AS med_count_24h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.deathtime, c.hospital_expire_flag
),
-- Assign quintiles based on med_count_24h
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_count_24h) AS quintile
  FROM medication_complexity
),
-- Calculate 30-day readmission: check if same patient had next admission within 30 days
readmission_flag AS (
  SELECT
    q.*,
    CASE
      WHEN LEAD(q.admittime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime) <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
        THEN 1 ELSE 0
    END AS thirty_day_readmit
  FROM quintiles q
),
-- Final aggregation by quintile
results AS (
  SELECT
    quintile,
    COUNT(*) AS num_patients,
    AVG(med_count_24h) AS mean_complexity_score,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / 3600 / 24) AS avg_los_days,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(thirty_day_readmit) AS thirty_day_readmission_rate
  FROM readmission_flag
  GROUP BY quintile
)
SELECT
  quintile,
  num_patients,
  ROUND(mean_complexity_score, 2) AS mean_complexity_score,
  ROUND(avg_los_days, 2) AS avg_los_days,
  ROUND(in_hospital_mortality_rate, 3) AS in_hospital_mortality_rate,
  ROUND(thirty_day_readmission_rate, 3) AS thirty_day_readmission_rate
FROM results
ORDER BY quintile;