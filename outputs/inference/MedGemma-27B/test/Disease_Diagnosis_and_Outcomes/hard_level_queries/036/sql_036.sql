WITH ComorbidityScore AS (
  SELECT
    subject_id,
    hadm_id,
    -- Calculate a simplified comorbidity score based on the number of diagnoses
    -- This is a placeholder for a more robust scoring system like Charlson or Elixhauser
    COUNT(DISTINCT icd_code) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
  GROUP BY
    subject_id,
    hadm_id
),
ComorbidityQuartile AS (
  SELECT
    subject_id,
    hadm_id,
    NTILE(4) OVER (ORDER BY num_diagnoses DESC) AS comorbidity_quartile
  FROM ComorbidityScore
),
PneumoniaDiagnosis AS (
  SELECT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code IN ('486', '487', '340.1', 'J18.9') -- Common ICD-9 codes for pneumonia
    AND icd_version = 9
  GROUP BY
    subject_id,
    hadm_id
),
PatientCohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN PneumoniaDiagnosis AS pn
    ON a.hadm_id = pn.hadm_id
  JOIN ComorbidityQuartile AS cq
    ON a.hadm_id = cq.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND cq.comorbidity_quartile = 4
),
CohortOutcomes AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    a.hospital_expire_flag,
    -- Calculate major complications (simplified example: need for mechanical ventilation or ICU stay)
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
          ON ce.itemid = di.itemid
        WHERE
          ce.subject_id = pc.subject_id
          AND ce.hadm_id = pc.hadm_id
          AND di.label = 'Mechanical Ventilation'
          AND ce.value = 'Yes'
      ) THEN 1
      ELSE 0
    END AS major_complication_flag,
    -- Calculate survival days (simplified: time from admission to discharge or death)
    -- Note: This is a simplified calculation and may not be accurate for all cases
    -- Consider using more robust survival analysis methods for clinical research
    -- Calculate survival days (simplified: time from admission to discharge or death)
    -- Note: This is a simplified calculation and may not be accurate for all cases
    -- Consider using more;