WITH hf_admissions AS (
  -- Step 1 & 2: male patients age 40-50 with a heart failure diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
admissions_with_readmit AS (
  -- Step 5a: flag 30-day readmissions
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    CASE
      WHEN LEAD(admittime) OVER (
             PARTITION BY subject_id
             ORDER BY admittime
           ) <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
      THEN 1 ELSE 0
    END AS readmit_30d
  FROM hf_admissions
),
med_complexity AS (
  -- Step 3: compute 7-day med complexity score per admission
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT p.drug) AS score
  FROM admissions_with_readmit a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON a.subject_id = p.subject_id
   AND a.hadm_id    = p.hadm_id
   AND p.starttime BETWEEN a.admittime
                       AND TIMESTAMP_ADD(a.admittime, INTERVAL 7 DAY)
  GROUP BY
    a.subject_id,
    a.hadm_id
),
scored AS (
  -- Step 4: assign quintiles
  SELECT
    m.subject_id,
    m.hadm_id,
    m.score,
    NTILE(5) OVER (ORDER BY m.score) AS quintile
  FROM med_complexity m
),
final_metrics AS (
  -- bring everything together
  SELECT
    s.quintile,
    s.subject_id,
    s.hadm_id,
    s.score,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.readmit_30d,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM scored s
  JOIN admissions_with_readmit a
    ON s.subject_id = a.subject_id
   AND s.hadm_id    = a.hadm_id
)
-- Step 6: aggregate by quintile
SELECT
  quintile,
  COUNT(DISTINCT subject_id)            AS patient_count,
  MIN(score)                            AS min_score,
  MAX(score)                            AS max_score,
  ROUND(AVG(los_days), 2)               AS mean_los_days,
  ROUND(AVG(hospital_expire_flag), 4)   AS in_hospital_mortality_rate,
  ROUND(AVG(readmit_30d), 4)            AS readmit_30d_rate
FROM final_metrics
GROUP BY quintile
ORDER BY quintile;