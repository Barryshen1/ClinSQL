WITH
-- Get male patients aged 83-93
male_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 83 AND 93
),

-- Get admissions with chest pain/AMI diagnoses
chest_pain_ami_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- Chest pain (R07) or AMI (I21) ICD codes
    (d.icd_code LIKE 'R07%' OR d.icd_code LIKE 'I21%')
    AND a.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Get first troponin T per admission (valuenum > 0.01)
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE
    di.label = 'Troponin T'
    AND l.valuenum > 0.01  -- 99th percentile threshold
    AND l.hadm_id IN (SELECT hadm_id FROM chest_pain_ami_admissions)
)

-- Final aggregation
SELECT
  COUNT(DISTINCT c.subject_id) AS N,
  AVG(p.anchor_age) AS mean_age,
  AVG(c.los_days) AS mean_los_days,
  AVG(f.troponin_value) AS mean_troponin,
  MIN(f.troponin_value) AS min_troponin,
  MAX(f.troponin_value) AS max_troponin
FROM
  chest_pain_ami_admissions c
JOIN
  male_patients p
  ON c.subject_id = p.subject_id
JOIN
  first_troponin f
  ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id AND f.rn = 1;