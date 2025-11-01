WITH PatientInfo AS (
  SELECT
    subject_id
  FROM patients
  WHERE
    gender = 'M' AND anchor_age = 63
),
DiagnosisInfo AS (
  SELECT DISTINCT
    p.subject_id
  FROM patients AS p
  JOIN diagnoses_icd AS d
    ON p.subject_id = d.subject_id
  JOIN d_icd_diagnoses AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    ) AND (
      icd.long_title LIKE '%type 2 diabetes%' OR icd.long_title LIKE '%diabetes mellitus type 2%'
    )
),
HeartFailureInfo AS (
  SELECT DISTINCT
    p.subject_id
  FROM patients AS p
  JOIN diagnoses_icd AS d
    ON p.subject_id = d.subject_id
  JOIN d_icd_diagnoses AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    ) AND (
      icd.long_title LIKE '%heart failure%'
    )
),
EligiblePatients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM admissions AS a
  JOIN PatientInfo AS pi
    ON a.subject_id = pi.subject_id
  JOIN DiagnosisInfo AS di
    ON a.subject_id = di.subject_id
  JOIN HeartFailureInfo AS hfi
    ON a.subject_id = hfi.subject_id
  WHERE
    a.dischtime - a.admittime >= INTERVAL '72' HOUR
),
GLP1AgonistInfo AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM prescriptions AS p
  JOIN d_items AS d
    ON p.drug = d.label -- Changed from p.drug_type = d.label to p.drug = d.label
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM EligiblePatients
    ) AND d.label = 'GLP-1 Agonist'
),
First72hGLP1 AS (
  SELECT
    ep.subject_id,
    ep.hadm_id
  FROM EligiblePatients AS ep
  JOIN GLP1AgonistInfo AS g
    ON ep.subject_id = g.subject_id AND ep.hadm_id = g.hadm_id
  WHERE
    g.starttime BETWEEN ep.admittime AND DATETIME_ADD(ep.admittime, INTERVAL '72' HOUR)
),
Final12hGLP1 AS (
  SELECT
    ep.subject_id,
    ep.hadm_id
  FROM EligiblePatients AS ep
  JOIN GLP1AgonistInfo AS g
    ON ep.subject_id = g.subject_id AND ep.hadm_id = g.hadm_id
  WHERE
    g.starttime BETWEEN DATETIME_SUB(ep.dischtime, INTERVAL '12' HOUR) AND ep.dischtime
),
GLP1Counts AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL '72' HOUR) THEN subject_id END) AS first72h_count,
    COUNT(DISTINCT CASE WHEN starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL '12' HOUR) AND dischtime THEN subject_id END) AS final12h_count
  FROM EligiblePatients AS ep
  JOIN GLP1AgonistInfo AS g
    ON ep.subject_id = g.subject_id AND ep.hadm_id = g.hadm_id
),
GLP1Percentages AS (
  SELECT
    (first72h_count / total_patients) * 100 AS first72h_percentage,
    (final12h_count / total_patients) * 100 AS final12h_percentage;