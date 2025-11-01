WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 89 AND 99
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code LIKE 'I63%'
    AND d.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), ICUStayInfo AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  WHERE
    i.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND i.hadm_id IN (
      SELECT
        hadm_id
      FROM
        AdmissionInfo
    )
), InstabilityScore AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    -- Calculate instability score for each patient's ICU stay
    -- This is a placeholder for the actual instability score calculation
    -- Replace this with the actual instability score calculation logic
    -- For example, using chartevents for vital signs
    -- SUM(CASE WHEN c.itemid IN (SELECT itemid FROM d_items WHERE label LIKE '%Heart Rate%') THEN 1 ELSE 0 END) AS instability_score
    -- This is a simplified example, the actual calculation is more complex
    -- and requires defining specific criteria for instability
    -- For demonstration purposes, we will use a placeholder value
    1 AS instability_score
  FROM
    ICUStayInfo AS i
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON i.subject_id = c.subject_id
    AND i.hadm_id = c.hadm_id
    AND i.stay_id = c.stay_id
  WHERE
    c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
), InstabilityScores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    instability_score
  FROM
    InstabilityScore
), PatientICUStay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    d.icd_code AS stroke_diagnosis
  FROM
    ICUStayInfo AS i
  JOIN
    PatientInfo AS p
    ON i.subject_id = p.subject_id
  JOIN
    AdmissionInfo AS a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN
    DiagnosisInfo AS d
    ON i.subject_id = d.;