WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.admission_type = 'EMERGENCY' -- Assuming PE is an emergency admission
),
MedicationComplexity AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    COUNT(DISTINCT e.emar_id) AS medication_count
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON pc.subject_id = e.subject_id AND pc.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 24 HOUR)
  GROUP BY
    pc.subject_id,
    pc.hadm_id
),
DrugRisk AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    CASE
      WHEN e.medication LIKE '%QT%' OR e.medication LIKE '%prolong%' THEN 1
      ELSE 0
    END AS qt_prolonging_flag,
    CASE
      WHEN e.medication LIKE '%warfarin%' OR e.medication LIKE '%heparin%' OR e.medication LIKE '%aspirin%' THEN 1
      ELSE 0
    END AS bleeding_risk_flag
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON pc.subject_id = e.subject_id AND pc.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 24 HOUR)
),
ICUComparison AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        WHERE
          icu.subject_id = pc.subject_id AND icu.hadm_id = pc.hadm_id
      ) THEN 1
      ELSE 0
    END AS icu_stay_flag
  FROM PatientCohort AS pc
),
LOSMortality AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pc.subject_id = a.subject_id AND pc.hadm_id = a.hadm_id -- Corrected join condition
)
SELECT
  mc.subject_id,
  mc.hadm_id,
  mc.medication_count,
  dr.qt_prolonging_flag,
  dr.bleeding_risk_flag,
  ic.icu_stay_flag,
  lm.dischtime,
  lm.deathtime,
  lm.hospital_expire_flag
FROM MedicationComplexity AS mc
INNER JOIN DrugRisk AS dr
  ON mc.subject_id = dr.subject_id AND mc.hadm_id = dr.hadm_id
INNER JOIN ICUComparison AS ic
  ON mc.subject_id = ic.subject_id AND mc.hadm_id = ic.hadm_id
INNER JOIN LOSMortality AS lm
  ON mc.subject_id = lm.subject_id AND mc.hadm_id = lm.hadm_id;