WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 39 AND 49
),
eligible_admissions AS (
  SELECT a.hadm_id, a.subject_id,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
  WHERE DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
acs_diagnoses AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%acute coronary syndrome%'
     OR long_title LIKE '%myocardial infarction%'
     OR long_title LIKE '%unstable angina%'
),
admissions_with_acs AS (
  SELECT a.hadm_id,
         MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) AS primary_acs,
         MAX(CASE WHEN di.seq_num > 1 THEN 1 ELSE 0 END) AS secondary_acs
  FROM eligible_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN acs_diagnoses acs ON di.icd_code = acs.icd_code AND di.icd_version = acs.icd_version
  GROUP BY a.hadm_id
),
ultrasound_counts AS (
  SELECT hadm_id, SUM(count) AS total_ultrasound
  FROM (
    SELECT hadm_id, COUNT(*) AS count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE d.long_title LIKE '%ultrasound%' 
       OR d.long_title LIKE '%echo%' 
       OR d.long_title LIKE '%echocardiogram%'
    GROUP BY hadm_id
    UNION ALL
    SELECT hadm_id, COUNT(*) AS count
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
      ON pe.itemid = d.itemid
    WHERE d.label LIKE '%ultrasound%' 
       OR d.label LIKE '%echo%' 
       OR d.label LIKE '%echocardiogram%'
    GROUP BY hadm_id
  ) AS combined
  GROUP BY hadm_id
)
SELECT 
  CASE WHEN los_days <= 4 THEN '1-4 days' ELSE '5-7 days' END AS los_group,
  CASE 
    WHEN primary_acs = 1 THEN 'primary' 
    WHEN secondary_acs = 1 THEN 'secondary' 
  END AS acs_type,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(uc.total_ultrasound, 0)) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(uc.total_ultrasound, 0)) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY COALESCE(uc.total_ultrasound, 0)) AS p75
FROM eligible_admissions a
LEFT JOIN admissions_with_acs acs ON a.hadm_id = acs.hadm_id
LEFT JOIN ultrasound_counts uc ON a.hadm_id = uc.hadm_id
WHERE (acs.primary_acs = 1 OR acs.secondary_acs = 1)
GROUP BY los_group, acs_type;