WITH PostCardiacArrestPatients AS (
  -- Identify patients with post-cardiac arrest diagnosis
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'I46.9' -- ICD-9 code for Cardiac arrest, unspecified
    OR d.icd_code = 'R92' -- ICD-10 code for Cardiac arrest
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
First48hEvents AS (
  -- Select relevant events within the first 48 hours of admission
  SELECT
    pca.subject_id,
    pca.hadm_id,
    pca.admittime,
    le.charttime,
    le.itemid,
    le.valuenum,
    le.valueuom,
    le.flag
  FROM PostCardiacArrestPatients AS pca
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pca.subject_id = le.subject_id AND pca.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN pca.admittime AND TIMESTAMP_ADD(pca.admittime, INTERVAL 48 HOUR)
),
InstabilityScore AS (
  -- Calculate the instability score based on critical lab events
  SELECT
    subject_id,
    hadm_id,
    -- Define instability score logic here based on lab values and flags
    -- Example: SUM(CASE WHEN itemid = XXX AND valuenum > YYY THEN 1 ELSE 0 END)
    -- This part needs specific clinical definition of instability score
    -- For demonstration, let's assume a simple score based on lactate
    CASE
      WHEN itemid = 51501 THEN
        CASE
          WHEN valuenum > 2.0 THEN 1
          ELSE 0
        END
      ELSE 0
    END AS lactate_score
  FROM First48hEvents
  WHERE
    itemid IN (51501) -- Lactate
  GROUP BY
    subject_id,
    hadm_id
),
CohortStats AS (
  -- Calculate cohort statistics (LOS, mortality)
  SELECT
    pca.subject_id,
    pca.hadm_id,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM PostCardiacArrestPatients AS pca
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pca.subject;