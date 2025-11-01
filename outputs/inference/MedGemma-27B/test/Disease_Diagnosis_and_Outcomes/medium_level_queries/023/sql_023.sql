WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 52 AND 62
), StrokeDiagnosis AS (
  SELECT
    p.subject_id,
    d.icd_code,
    d.icd_version
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code LIKE 'I63%' -- Ischemic stroke
    OR d.icd_code LIKE 'I60%' -- Hemorrhagic stroke
), StrokeType AS (
  SELECT
    s.subject_id,
    CASE
      WHEN s.icd_code LIKE 'I63%'
      THEN 'Ischemic'
      WHEN s.icd_code LIKE 'I60%'
      THEN 'Hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM StrokeDiagnosis AS s
), Comorbidity AS (
  SELECT
    p.subject_id,
    CASE
      WHEN d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E10%'
      THEN 'Diabetes'
      WHEN d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'I12%'
      THEN 'CKD'
      ELSE NULL
    END AS comorbidity
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'I12%'
), ComorbidityTertile AS (
  SELECT
    subject_id,
    COUNT(comorbidity) AS comorbidity_count
  FROM Comorbidity
  GROUP BY
    subject_id
), Mortality AS (
  SELECT
    p.subject_id,
    CASE
      WHEN a.deathtime IS NOT NULL
      THEN 1
      ELSE 0
    END AS mortality
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
), LOS AS (
  SELECT
    p.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
), FinalData AS (
  SELECT
    p.subject_id,
    st.stroke_type,
    m.mortality,
    l.los,
    c.comorbidity_count
  FROM PatientInfo AS p
  JOIN StrokeType AS st
    ON p.subject_id = st.subject_id
  JOIN Mortality AS m
    ON p.subject_id = m.subject_id
  JOIN LOS AS l
    ON p.subject_id = l.subject_id
  JOIN ComorbidityTertile AS c
    ON p.subject_id = c.subject_id
)
SELECT
  stroke_type,
  COUNT(subject_id) AS total_patients,
  SUM(mortality) * 100.0 / COUNT(subject_id) AS mortality_percentage,
  AVG(los) AS average_los,
  AVG(comorbidity_count) AS average_com;