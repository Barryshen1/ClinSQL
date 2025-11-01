WITH PatientCohort AS (
  -- Select patients meeting the criteria: female, age 45-55, multi-trauma
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.admission_type = 'EMERGENCY' -- Assuming multi-trauma patients are admitted via emergency
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'S06%' -- ICD-10 codes for multiple injuries (S06.0-S06.9)
    )
),

MedicationComplexity AS (
  -- Calculate medication complexity score for each patient admission
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.deathtime,
    pc.hospital_expire_flag,
    COUNT(DISTINCT e.drug) AS medication_complexity_score
  FROM
    PatientCohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON pc.subject_id = e.subject_id
    AND pc.hadm_id = e.hadm_id
    AND e.charttime BETWEEN pc.admittime AND DATE_ADD(pc.admittime, INTERVAL 7 DAY)
  GROUP BY
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.deathtime,
    pc.hospital_expire_flag
),

Tertiles AS (
  -- Stratify medication complexity into tertiles
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.medication_complexity_score,
    NTILE(3) OVER (ORDER BY mc.medication_complexity_score) AS complexity_tertile
  FROM
    MedicationComplexity AS mc
),

AdmissionStats AS (
  -- Calculate admission statistics per tertile
  SELECT
    t.complexity_tertile,
    COUNT(DISTINCT t.hadm_id) AS admissions,
    AVG(mc.medication_complexity_score) AS mean_score,
    MIN(mc.medication_complexity_score) AS min_score,
    MAX(mc.medication_complexity_score) AS max_score,
    AVG(TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY)) AS mean_los, -- Calculate mean LOS in days
    AVG(CASE WHEN t.hospital_expire_flag = TRUE THEN 1 ELSE 0 END) AS mortality_percent, -- Calculate mortality percentage
    AVG(CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = t.subject_id
      AND a2.admittime > t.dischtime
      AND a2.admittime <= DATE_ADD(t.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END) AS readmission_percent -- Calculate 30-day readmission percentage
  FROM
    Tertiles AS t
  INNER JOIN
    MedicationComplexity AS mc
    ON t.hadm_id = mc.hadm_id
  GROUP BY
    t.complexity_tertile
)

SELECT
  *
FROM
  AdmissionStats
ORDER BY
  complexity_tertile;