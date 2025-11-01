WITH stroke_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND d.seq_num = 1
    AND d.icd_code LIKE 'I63%'
    AND a.hospital_expire_flag = 0
),
los_calc AS (
  SELECT
    subject_id,
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM stroke_patients
  WHERE rn = 1
    AND dischtime > admittime  -- Ensure positive LOS
)
SELECT
  PERCENTILE_CONT(los_days, 0.5) AS median_los_days
FROM los_calc
WHERE los_days > 0
  AND los_days IS NOT NULL;