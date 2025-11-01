WITH Cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    di.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND di.long_title LIKE '%lower GI bleed%'
    AND a.admittime BETWEEN TIMESTAMP_SUB(a.admittime, INTERVAL 72 HOUR) AND a.admittime
), LabInstability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.charttime,
    c.valuenum,
    c.valueuom,
    d.label AS lab_name
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d ON c.itemid = d.itemid
  WHERE
    c.subject_id IN (SELECT subject_id FROM Cohort)
    AND c.hadm_id IN (SELECT hadm_id FROM Cohort)
    AND c.charttime BETWEEN (SELECT MIN(admittime) FROM Cohort WHERE subject_id = c.subject_id AND hadm_id = c.hadm_id) AND (SELECT MIN(admittime) FROM Cohort WHERE subject_id = c.subject_id AND hadm_id = c.hadm_id) + INTERVAL 72 HOUR
    AND d.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Diastolic Blood Pressure', 'Respiratory Rate', 'Oxygen Saturation', 'Temperature')
), LabInstabilityScore AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(*) AS instability_score
  FROM
    LabInstability
  GROUP BY
    subject_id,
    hadm_id
), CohortStats AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    di.long_title AS diagnosis,
    lis.instability_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    INNER JOIN LabInstabilityScore AS lis ON a.subject_id = lis.subject_id AND a.hadm_id = lis.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND di.long_title LIKE '%lower GI bleed%'
    AND a.admittime BETWEEN TIMESTAMP_SUB(;