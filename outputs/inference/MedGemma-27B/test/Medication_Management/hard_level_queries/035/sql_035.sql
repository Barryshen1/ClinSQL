WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 40 AND 50
), NeutropenicFever AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON d.subject_id = p.subject_id
  WHERE
    icd.long_title LIKE '%neutropenia%'
    AND icd.long_title LIKE '%fever%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
), MedicationComplexity AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT e.medication) AS medication_complexity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS e ON a.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    a.hadm_id
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_type,
    a.admission_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    NeutropenicFever AS nf ON a.hadm_id = nf.hadm_id
  JOIN
    PatientInfo AS pi ON a.hadm_id = pi.hadm_id
), Readmission AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_type,
    a.admission_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.admittime > TIMESTAMP_ADD(
      (
        SELECT
          MAX(dischtime)
        FROM
          `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      ), INTERVAL 30 DAY
    )
), FinalData AS (
  SELECT
    ai.hadm_id,
    ai.admittime,
    ai.dischtime,
    ai.deathtime,
    ai.hospital_expire_flag,
    mc.medication_complexity_score,
    CASE
      WHEN ai.hospital_expire_flag = TRUE THEN 1
      ELSE 0
    END AS mortality_flag,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM
          Readmission AS r
        WHERE
          r.subject_id = ai.subject_id AND r.admittime > ai.dischtime
      ) THEN 1
      ELSE 0
    END AS readmission_flag
  FROM
    AdmissionInfo AS ai
  JOIN
    MedicationComplexity AS mc ON ai.hadm_id = mc.hadm_id
), Quartiles AS (
  SELECT
    hadm_id,
    medication_complexity_score,
    NTILE(4) OVER (ORDER BY medication_complexity_score) AS;