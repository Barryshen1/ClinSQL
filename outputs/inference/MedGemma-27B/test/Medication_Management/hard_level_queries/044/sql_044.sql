WITH PatientPE AS (
  -- Identify patients with PE diagnosis
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = 'I26.9' -- PE diagnosis code
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
),
First24HoursMeds AS (
  -- Count distinct medications for each patient in the first 24 hours of admission
  SELECT
    a.subject_id,
    COUNT(DISTINCT e.medication) AS distinct_meds
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON a.hadm_id = e.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientPE)
    AND e.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
  GROUP BY
    a.subject_id
),
MedComplexityTertiles AS (
  -- Stratify patients into tertiles based on medication complexity
  SELECT
    subject_id,
    distinct_meds,
    NTILE(3) OVER (ORDER BY distinct_meds) AS med_tertile
  FROM First24HoursMeds
),
AdmissionData AS (
  -- Calculate admission-level metrics for each patient
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_type,
    a.los,
    CASE
      WHEN a.hospital_expire_flag = TRUE THEN 1
      ELSE 0
    END AS mortality_flag,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 0
      ELSE 1
    END AS readmission_flag -- Assuming readmission if not discharged home
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientPE)
),
ReadmissionData AS (
  -- Calculate 30-day readmission rate
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(CASE
      WHEN r.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END) AS readmission_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS r
    ON a.subject_id = r.subject_id
    AND r.admittime BETWEEN TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY) AND TIMESTAMP_ADD(a.dischtime, INTERVAL 31 DAY)
  GROUP BY
    a.subject_id,
    a.hadm_id
),
FinalData AS (
  -- Combine all data and calculate final metrics
  SELECT
    a.subject_id,
    a.hadm_id,
    mt.med_tertile,
    a.mortality_flag,
    rd.readmission_count,
    a.los
  FROM AdmissionData AS a
  JOIN MedComplexityTertiles AS mt
    ON a.subject_id = mt.subject_id
  JOIN ReadmissionData AS rd
    ON a.subject_id = rd.subject_id
    AND a.hadm_id = rd.hadm_id
)
SELECT
  med_tertile,
  COUNT(subject_id) AS admissions,
  AVG(los) AS avg_los,
  AVG(mortality_flag) AS mortality_percentage,
  AVG(readmission_count) AS readmission_percentage;