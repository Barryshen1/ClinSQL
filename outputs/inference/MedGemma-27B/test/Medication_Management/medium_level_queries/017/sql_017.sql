WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    -- Extract year of birth from anchor_age and anchor_year
    EXTRACT(YEAR FROM DATE(anchor_year, anchor_age)) AS birth_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), DiagnosisInfo AS (
  SELECT
    subject_id,
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
), MedicationInfo AS (
  SELECT
    subject_id,
    hadm_id,
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE
    drug NOT LIKE '%[A-Z]%' -- Exclude non-standard drug names
), ICUStayInfo AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
), CombinedInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.birth_year,
    d.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    PatientInfo AS p
    JOIN DiagnosisInfo AS d ON p.subject_id = d.subject_id
    JOIN ICUStayInfo AS i ON p.subject_id = i.subject_id AND d.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.birth_year BETWEEN 1981 AND 1987 -- 42 years old in 2023, so born between 1981 and 1987
    AND d.icd_code IN ('250', '350', '362') -- Diabetes codes
    AND d.icd_code IN ('428', '4280', '4281', '4282', '4283', '4284', '4289') -- Heart failure codes
    AND i.los >= 144
), MedicationUsage AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    m.drug,
    CASE
      WHEN m.charttime >= c.intime AND m.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR) THEN 'First 72h'
      WHEN m.charttime >= TIMESTAMP_SUB(c.outtime, INTERVAL 72 HOUR) AND m.charttime <= c.outtime THEN 'Final 72h'
      ELSE 'Other'
    END AS time_period,
    CASE
      WHEN m.charttime >= c.intime AND m.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR) THEN 1
      WHEN;