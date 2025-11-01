WITH PatientMedComplexity AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate medication complexity score (e.g., number of unique medications)
    COUNT(DISTINCT e.drug) AS medication_complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON a.hadm_id = e.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.admission_type = 'EMERGENCY' -- Assuming cardiac arrest is an emergency admission
    AND EXISTS (
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I46%' -- ICD-10 code for cardiac arrest
    )
  GROUP BY
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
),
MedComplexityQuintiles AS (
  SELECT
    subject_id,
    medication_complexity_score,
    NTILE(5) OVER (ORDER BY medication_complexity_score) AS complexity_quintile
  FROM PatientMedComplexity
),
ReadmissionStatus AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    -- Check for readmission within 30 days
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = a.subject_id
          AND a2.admittime > a.dischtime
          AND a2.admittime <= DATETIME_ADD(a.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
)
SELECT
  mcq.complexity_quintile,
  COUNT(DISTINCT mcq.subject_id) AS patient_count,
  AVG(mcq.medication_complexity_score) AS avg_score,
  MIN(mcq.medication_complexity_score) AS min_score,
  MAX(mcq.medication_complexity_score) AS max_score,
  AVG(a.los) AS avg_los,
  AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_percent,
  AVG(rs.readmitted_30_days) AS readmission_percent
FROM MedComplexityQuintiles AS mcq
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON mcq.subject_id = a.subject_id
JOIN ReadmissionStatus AS rs
  ON mcq.subject_id = rs.subject_id
GROUP BY
  mcq.complexity_quintile;