WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 46 AND 56
),
DiagnosisInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    d.icd_code
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'I21.9' -- Acute myocardial infarction
),
ComplicationInfo AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS num_complications
  FROM
    DiagnosisInfo AS di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON di.subject_id = d.subject_id AND di.hadm_id = d.hadm_id
  WHERE
    d.icd_code NOT IN ('I21.9', 'I22.9', 'I23.9', 'I24.9', 'I25.9', 'I26.9', 'I27.9', 'I28.9', 'I29.9', 'I30.9', 'I31.9', 'I32.9', 'I33.9', 'I34.9', 'I35.9', 'I36.9', 'I37.9', 'I38.9', 'I39.9', 'I40.9', 'I41.9', 'I42.9', 'I43.9', 'I44.9', 'I45.9', 'I46.9', 'I47.9', 'I48.9', 'I49.9', 'I50.9', 'I51.9', 'I52.9', 'I53.9', 'I54.9', 'I55.9', 'I56.9', 'I57.9', 'I58.9', 'I59.9', 'I60.9', 'I61.9', 'I62.9', 'I63.9', 'I64.9', 'I65.9', 'I66.9', 'I67.9', 'I68.9', 'I69.9', 'I70.9', 'I71.9', 'I72.9', 'I73.9', 'I74.9', 'I75.9', 'I76.9', 'I77.9', 'I78.9', 'I79.9', 'I80.9', 'I81.9', 'I82.9', 'I83.9', 'I84.9', 'I85.9', 'I8;