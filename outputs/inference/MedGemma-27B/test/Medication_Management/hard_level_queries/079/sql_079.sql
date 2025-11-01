WITH PatientCohort AS (
  -- Select patients meeting the criteria: male, age 89-99, hemorrhagic stroke
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type = 'EMERGENCY' -- Assuming hemorrhagic stroke is typically an emergency admission
    AND EXISTS (
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I60%' -- ICD-10 codes for intracerebral hemorrhage
        AND d.icd_version = 10
    )
), MedicationComplexity AS (
  -- Calculate medication complexity (unique drugs in first 7 days)
  SELECT
    pc.subject_id,
    pc.hadm_id,
    COUNT(DISTINCT e.medication) AS unique_meds -- Changed 'drug' to 'medication'
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON pc.subject_id = e.subject_id AND pc.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN pc.admittime AND DATE_ADD(pc.admittime, INTERVAL 7 DAY)
  GROUP BY
    pc.subject_id,
    pc.hadm_id
), Quintiles AS (
  -- Assign patients to medication complexity quintiles
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.unique_meds,
    NTILE(5) OVER (ORDER BY mc.unique_meds ASC) AS complexity_quintile
  FROM MedicationComplexity AS mc
), OutcomeData AS (
  -- Calculate LOS, inpatient mortality, and 30-day readmission
  SELECT
    q.subject_id,
    q.hadm_id,
    q.complexity_quintile,
    a.los,
    a.hospital_expire_flag,
    -- Calculate 30-day readmission
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = q.subject_id
          AND a2.admittime BETWEEN DATE_ADD(a.dischtime, INTERVAL 1 DAY) AND DATE_ADD(a.dischtime, INTERVAL 30 DAY)
          AND a2.hadm_id != a.hadm_id
      ) THEN 1
      ELSE 0
    END AS readmitted_30_days
  FROM Quintiles AS q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON q.hadm_id = a.hadm_id
)
-- Final aggregation by quintile
SELECT
  complexity_quintile,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS inpatient_mortality_rate,
  AVG(readmitted_30_days) AS readmission;