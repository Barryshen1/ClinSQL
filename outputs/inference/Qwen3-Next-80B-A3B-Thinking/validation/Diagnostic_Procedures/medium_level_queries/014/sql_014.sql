WITH acs_admissions AS (
  SELECT 
    d.hadm_id,
    MIN(CASE 
      WHEN LOWER(d_icd.long_title) LIKE '%acute coronary syndrome%' 
        OR LOWER(d_icd.long_title) LIKE '%myocardial infarction%' 
        OR LOWER(d_icd.long_title) LIKE '%unstable angina%' 
      THEN d.seq_num 
      ELSE NULL 
    END) AS min_acs_seq
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  GROUP BY d.hadm_id
),
ultrasound_counts AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` USING (itemid)
    WHERE LOWER(label) LIKE '%ultrasound%'
    UNION ALL
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE LOWER(short_description) LIKE '%ultrasound%'
  ) AS all_ultrasounds
  GROUP BY hadm_id
),
admissions_with_los AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN acs.min_acs_seq = 1 THEN 'primary'
      WHEN acs.min_acs_seq > 1 THEN 'secondary'
      ELSE NULL 
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN acs_admissions acs ON a.hadm_id = acs.hadm_id
  WHERE acs.min_acs_seq IS NOT NULL
),
patients_filtered AS (
  SELECT 
    subject_id,
    anchor_age,
    gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 83 AND 93
)
SELECT 
  CASE 
    WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN a.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE NULL 
  END AS los_group,
  a.diagnosis_type,
  AVG(COALESCE(u.ultrasound_count, 0)) AS mean_ultrasounds,
  MIN(COALESCE(u.ultrasound_count, 0)) AS min_ultrasounds,
  MAX(COALESCE(u.ultrasound_count, 0)) AS max_ultrasounds
FROM admissions_with_los a
JOIN patients_filtered p ON a.subject_id = p.subject_id
LEFT JOIN ultrasound_counts u ON a.hadm_id = u.hadm_id
WHERE a.los_days BETWEEN 1 AND 7
GROUP BY los_group, diagnosis_type;