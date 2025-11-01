WITH PatientCohort AS (
  -- Select patients meeting the criteria: female, age 87-97, diagnosed with ICH
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime -- Added admittime to the PatientCohort CTE
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND d.icd_code LIKE 'I60%' -- ICH codes start with I60
    AND a.admission_type = 'EMERGENCY' -- Assuming ICH admissions are typically emergency
),

MedicationComplexity AS (
  -- Calculate medication complexity (unique drugs + routes) in the first 48 hours
  SELECT
    pc.subject_id,
    pc.hadm_id,
    COUNT(DISTINCT CONCAT(m.medication, m.route)) AS medication_complexity_score
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS m
    ON pc.subject_id = m.subject_id AND pc.hadm_id = m.hadm_id
  WHERE
    m.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 48 HOUR)
  GROUP BY
    pc.subject_id,
    pc.hadm_id
),

Quartiles AS (
  -- Assign patients to medication complexity quartiles
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.medication_complexity_score,
    NTILE(4) OVER (ORDER BY mc.medication_complexity_score) AS complexity_quartile
  FROM MedicationComplexity AS mc
),

AdmissionStats AS (
  -- Calculate admission statistics (LOS, mortality, readmission)
  SELECT
    q.subject_id,
    q.hadm_id,
    q.complexity_quartile,
    q.medication_complexity_score,
    a.los AS hospital_los,
    CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality_flag,
    -- Calculate 30-day readmission flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = a.subject_id
        AND a2.admittime BETWEEN TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY) AND TIMESTAMP_ADD(a.dischtime, INTERVAL 31 DAY)
    ) THEN 1 ELSE 0 END AS readmission_30day_flag
  FROM Quartiles AS q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON q.hadm_id = a.hadm_id
)

-- Final aggregation to report results by complexity quartile
SELECT
  complexity_quartile,
  COUNT(DISTINCT subject_id) AS admissions,
  MIN(medication_complexity_score) AS score_range_min,
  MAX(medication_complexity_score) AS score_range_max,
  AVG(hospital_los) AS avg_los,
  AVG(mortality_flag) AS mortality,
  AVG(readmission_30day_flag) AS readmission_30day_percent
FROM AdmissionStats
GROUP BY
  complexity_quartile;