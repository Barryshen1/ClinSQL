WITH
-- Step 1: Identify male patients aged 40-50 with heart failure
hf_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND diag.long_title LIKE '%heart failure%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Step 2: Calculate 7-day medication complexity score
med_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS unique_meds_7day
  FROM (
    SELECT
      p.subject_id,
      p.hadm_id,
      p.drug,
      DATE(p.starttime) AS med_date
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN
      hf_patients h ON p.subject_id = h.subject_id AND p.hadm_id = h.hadm_id
    WHERE
      p.starttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 7 DAY)
      AND p.drug IS NOT NULL
    GROUP BY
      subject_id, hadm_id, drug, med_date
  )
  GROUP BY
    subject_id, hadm_id
),

-- Step 3: Stratify by quintiles
quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    unique_meds_7day,
    NTILE(5) OVER (ORDER BY unique_meds_7day) AS quintile
  FROM
    med_complexity
),

-- Step 4: Calculate 30-day readmission
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS original_hadm_id,
    a2.hadm_id AS readmit_hadm_id,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmit
  FROM
    hf_patients a1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id
  WHERE
    a2.admittime > a1.dischtime
    AND TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
    AND a2.admittime IS NOT NULL
    AND a2.dischtime IS NOT NULL
)

-- Final output
SELECT
  q.quintile,
  MIN(mc.unique_meds_7day) AS min_score,
  MAX(mc.unique_meds_7day) AS max_score,
  COUNT(DISTINCT q.subject_id) AS patient_count,
  ROUND(AVG(h.los_days), 2) AS mean_los_days,
  SUM(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality,
  COUNT(DISTINCT r.original_hadm_id) AS readmissions_30day
FROM
  quintiles q
JOIN
  med_complexity mc ON q.subject_id = mc.subject_id AND q.hadm_id = mc.hadm_id
JOIN
  hf_patients h ON q.subject_id = h.subject_id AND q.hadm_id = h.hadm_id
LEFT JOIN
  readmissions r ON q.subject_id = r.subject_id AND q.hadm_id = r.original_hadm_id
GROUP BY
  q.quintile
ORDER BY
  q.quintile;