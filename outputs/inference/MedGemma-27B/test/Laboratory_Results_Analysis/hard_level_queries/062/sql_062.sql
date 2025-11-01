WITH PatientInfo AS (
  -- Select subject_id and age for the specific patient
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 48
),

Cohort AS (
  -- Define the cohort: female admissions aged 43-53 with sepsis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    d.icd_code AS sepsis_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1 -- Assuming first diagnosis is the primary one
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 43 AND 53
    AND d.icd_code IN ('A41.9', 'A41.4', 'A41.5', 'A41.2', 'A41.1', 'A41.0', 'A41.3', 'A41.8') -- Sepsis ICD-9 codes
    AND a.hospital_expire_flag = 0 -- Exclude patients who died in hospital
),

CriticalLabEvents AS (
  -- Identify critical lab events based on predefined criteria
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.itemid,
    le.value,
    le.valuenum,
    le.valueuom,
    li.label AS lab_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE
    le.itemid IN (50912, 50911, 50910, 50909, 50908, 50907, 50906, 50905, 50904, 50903, 50902, 50901, 50900, 50899, 50898, 50897, 50896, 50895, 50894, 50893, 50892, 50891, 50890, 50889, 50888) -- Removed trailing semicolon
),

InstabilityScore AS (
  -- Calculate the instability score (critical lab event count) for each admission within the first 72 hours
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(cle.itemid) AS critical_event_count
  FROM
    Cohort AS c
  JOIN
    CriticalLabEvents AS cle
    ON c.subject_id = cle.subject_id AND c.hadm_id = cle.hadm_id
  WHERE
    cle.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id,
    c.hadm_id
),

PatientInstability AS (
  -- Calculate the 25th percentile instability score for the specific patient
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    PERCENTILE_CONT(is.critical_event_count, 0.25) OVER (PARTITION BY p.subject_;