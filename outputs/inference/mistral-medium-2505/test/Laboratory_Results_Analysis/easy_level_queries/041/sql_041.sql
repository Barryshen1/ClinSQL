WITH
-- Step 1: Identify male patients aged 45-55
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 45 AND 55
),

-- Step 2: Identify pneumonia admissions (ICD-10 codes J12-J18 or J69.0)
pneumonia_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND (
      (di.icd_code LIKE 'J12%' OR di.icd_code LIKE 'J13%' OR di.icd_code LIKE 'J14%'
       OR di.icd_code LIKE 'J15%' OR di.icd_code LIKE 'J16%' OR di.icd_code LIKE 'J17%'
       OR di.icd_code LIKE 'J18%')
      OR di.icd_code = 'J69.0'
    )
),

-- Step 3: Get creatinine lab events in the first 24 hours
creatinine_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  JOIN
    pneumonia_admissions pa
    ON l.subject_id = pa.subject_id AND l.hadm_id = pa.hadm_id
  WHERE
    dl.label = 'Creatinine'
    AND l.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
),

-- Step 4: Calculate average creatinine per admission
avg_creatinine AS (
  SELECT
    hadm_id,
    AVG(valuenum) AS avg_creatinine
  FROM
    creatinine_labs
  GROUP BY
    hadm_id
  HAVING
    COUNT(valuenum) > 0  -- Ensure at least one measurement exists
)

-- Step 5: Compute standard deviation of average creatinine
SELECT
  STDDEV(avg_creatinine) AS sd_avg_creatinine
FROM
  avg_creatinine;